"""Amigos, presença, grupos, convites e eventos (GAME_DESIGN §10, ARCHITECTURE §5).

Amizades ficam no banco. Grupos, convites e presença ficam em memória: se o
meta-servidor reiniciar, cada um volta a ficar sozinho no próprio grupo, o que
é aceitável para um grupo de amigos.

Eventos: cada conta tem uma fila com número de sequência. O cliente faz
GET /v1/events?since=N (long-polling): a resposta volta assim que houver evento
novo, ou vazia depois de alguns segundos.
"""
import asyncio
import secrets
import time

from .http import HttpError

GRUPO_MAX = 4
CONVITE_TTL_S = 300
ONLINE_S = 45          # sem pedidos há mais que isso = offline
EVENTOS_GUARDADOS = 100
MODOS = ("br", "treino")


class Eventos:
    def __init__(self):
        self._filas: dict[int, list] = {}
        self._seq: dict[int, int] = {}
        self._sinal: dict[int, asyncio.Event] = {}

    def emitir(self, conta: int, tipo: str, dados: dict | None = None) -> None:
        seq = self._seq.get(conta, 0) + 1
        self._seq[conta] = seq
        fila = self._filas.setdefault(conta, [])
        fila.append({"seq": seq, "type": tipo, "data": dados or {}, "time": int(time.time())})
        del fila[:-EVENTOS_GUARDADOS]
        ev = self._sinal.get(conta)
        if ev:
            ev.set()

    def ultimo(self, conta: int) -> int:
        return self._seq.get(conta, 0)

    def desde(self, conta: int, since: int) -> list:
        return [e for e in self._filas.get(conta, []) if e["seq"] > since]

    async def esperar(self, conta: int, since: int, limite_s: float) -> list:
        novos = self.desde(conta, since)
        if novos or limite_s <= 0:
            return novos
        ev = self._sinal.setdefault(conta, asyncio.Event())
        ev.clear()
        try:
            await asyncio.wait_for(ev.wait(), limite_s)
        except asyncio.TimeoutError:
            pass
        return self.desde(conta, since)


class Grupo:
    def __init__(self, lider: int):
        self.id = secrets.token_hex(6)
        self.lider = lider
        self.membros: list[int] = [lider]
        self.modo = "br"
        self.estado = "lobby"          # lobby | fila | partida
        self.fila_desde = 0.0
        self.partida: dict | None = None   # {host, port, room, private_code}


class Social:
    def __init__(self, con, contas, eventos: Eventos):
        self.con = con
        self.contas = contas
        self.ev = eventos
        self.visto: dict[int, float] = {}
        self.status: dict[int, str] = {}       # conta -> lobby | fila | partida
        self.grupo_de: dict[int, Grupo] = {}
        self.convites: dict[str, dict] = {}    # id -> {de, para, grupo, expira}
        self.ao_mudar_grupo = None             # callback (grupo) — o matchmaking cancela a fila
        self.traje_de = lambda conta: ""       # App liga à progressão (lobby mostra o traje de cada um)

    # ---------- presença ----------
    def tocar(self, conta: int) -> None:
        era_online = self.online(conta)
        self.visto[conta] = time.monotonic()
        if not era_online:
            self._avisar_amigos(conta)

    def online(self, conta: int) -> bool:
        return time.monotonic() - self.visto.get(conta, -1e9) < ONLINE_S

    def presenca(self, conta: int) -> str:
        if not self.online(conta):
            return "offline"
        g = self.grupo_de.get(conta)
        return g.estado if g else "lobby"

    def _avisar_amigos(self, conta: int) -> None:
        for amigo in self.amigos_ids(conta):
            self.ev.emitir(amigo, "friends", {})

    def expirar(self) -> None:
        """Chamado periodicamente: avisa quem ficou offline e limpa convites velhos."""
        agora = time.monotonic()
        for conta, t in list(self.visto.items()):
            if agora - t >= ONLINE_S:
                del self.visto[conta]
                self._avisar_amigos(conta)
                g = self.grupo_de.get(conta)
                if g and len(g.membros) > 1 and g.estado == "lobby":
                    self.sair_do_grupo(conta)
        for cid, c in list(self.convites.items()):
            if c["expira"] < time.time():
                del self.convites[cid]

    # ---------- amigos ----------
    @staticmethod
    def _par(x: int, y: int) -> tuple[int, int]:
        return (x, y) if x < y else (y, x)

    def amigos_ids(self, conta: int) -> list[int]:
        rows = self.con.execute("SELECT a, b FROM friendships WHERE status = 'accepted' AND (a = ? OR b = ?)",
                                (conta, conta)).fetchall()
        return [r["b"] if r["a"] == conta else r["a"] for r in rows]

    def lista_amigos(self, conta: int) -> dict:
        rows = self.con.execute("SELECT * FROM friendships WHERE a = ? OR b = ?", (conta, conta)).fetchall()
        amigos, recebidos, enviados = [], [], []
        for r in rows:
            outro = r["b"] if r["a"] == conta else r["a"]
            info = self.contas.publica(outro)
            if r["status"] == "accepted":
                info["status"] = self.presenca(outro)
                g = self.grupo_de.get(outro)
                info["party_size"] = len(g.membros) if g else 1
                amigos.append(info)
            elif r["requester"] == conta:
                enviados.append(info)
            else:
                recebidos.append(info)
        ordem = {"lobby": 0, "fila": 1, "partida": 2, "offline": 3}
        amigos.sort(key=lambda a: (ordem.get(a["status"], 9), a["username"].casefold()))
        return {"friends": amigos, "incoming": recebidos, "outgoing": enviados}

    def pedir_amizade(self, conta: int, nome: str) -> dict:
        outro = self.contas.por_nome(nome)
        if outro is None:
            raise HttpError(404, "Ninguém com esse nome.")
        if outro == conta:
            raise HttpError(400, "Você não pode adicionar a si mesmo.")
        a, b = self._par(conta, outro)
        row = self.con.execute("SELECT * FROM friendships WHERE a = ? AND b = ?", (a, b)).fetchone()
        if row:
            if row["status"] == "accepted":
                raise HttpError(409, "Vocês já são amigos.")
            if row["requester"] == outro:      # o outro já tinha pedido: aceita
                return self.responder_amizade(conta, outro, True)
            raise HttpError(409, "Pedido já enviado.")
        self.con.execute("INSERT INTO friendships VALUES (?, ?, ?, 'pending', ?)", (a, b, conta, int(time.time())))
        self.ev.emitir(outro, "friend_request", {"from": self.contas.publica(conta)})
        return {"status": "pending"}

    def responder_amizade(self, conta: int, outro: int, aceitar: bool) -> dict:
        a, b = self._par(conta, int(outro))
        row = self.con.execute("SELECT * FROM friendships WHERE a = ? AND b = ? AND status = 'pending'", (a, b)).fetchone()
        if row is None or row["requester"] == conta:
            raise HttpError(404, "Pedido não encontrado.")
        if aceitar:
            self.con.execute("UPDATE friendships SET status = 'accepted' WHERE a = ? AND b = ?", (a, b))
        else:
            self.con.execute("DELETE FROM friendships WHERE a = ? AND b = ?", (a, b))
        self.ev.emitir(int(outro), "friends", {})
        self.ev.emitir(conta, "friends", {})
        return {"status": "accepted" if aceitar else "declined"}

    def remover_amigo(self, conta: int, outro: int) -> dict:
        a, b = self._par(conta, int(outro))
        self.con.execute("DELETE FROM friendships WHERE a = ? AND b = ?", (a, b))
        self.ev.emitir(int(outro), "friends", {})
        return {"status": "removed"}

    # ---------- grupos ----------
    def grupo(self, conta: int) -> Grupo:
        g = self.grupo_de.get(conta)
        if g is None:
            g = Grupo(conta)
            self.grupo_de[conta] = g
        return g

    def grupo_dict(self, g: Grupo) -> dict:
        return {"id": g.id, "leader": g.lider, "mode": g.modo, "state": g.estado,
                "members": [{**self.contas.publica(m), "leader": m == g.lider, "traje": self.traje_de(m)} for m in g.membros],
                "queue_s": int(time.monotonic() - g.fila_desde) if g.estado == "fila" else 0,
                "match": g.partida}

    def _avisar_grupo(self, g: Grupo) -> None:
        d = self.grupo_dict(g)
        for m in g.membros:
            self.ev.emitir(m, "party", d)
            for amigo in self.amigos_ids(m):
                self.ev.emitir(amigo, "friends", {})

    def _mudou(self, g: Grupo) -> None:
        if self.ao_mudar_grupo:
            self.ao_mudar_grupo(g)
        self._avisar_grupo(g)

    def convidar(self, conta: int, outro: int) -> dict:
        outro = int(outro)
        if outro not in self.amigos_ids(conta):
            raise HttpError(403, "Só dá para convidar amigos.")
        if not self.online(outro):
            raise HttpError(409, "Esse amigo está offline.")
        g = self.grupo(conta)
        if outro in g.membros:
            raise HttpError(409, "Já está no seu grupo.")
        if len(g.membros) >= GRUPO_MAX:
            raise HttpError(409, f"O grupo já tem {GRUPO_MAX} jogadores.")
        cid = secrets.token_hex(8)
        self.convites[cid] = {"id": cid, "from": conta, "to": outro, "party": g.id, "expira": time.time() + CONVITE_TTL_S}
        self.ev.emitir(outro, "invite", {"id": cid, "from": self.contas.publica(conta), "party_size": len(g.membros)})
        return {"invite": cid}

    def responder_convite(self, conta: int, cid: str, aceitar: bool) -> dict:
        c = self.convites.pop(cid, None)
        if c is None or c["to"] != conta or c["expira"] < time.time():
            raise HttpError(404, "Convite expirado.")
        if not aceitar:
            self.ev.emitir(c["from"], "invite_declined", {"by": self.contas.publica(conta)})
            return {"status": "declined"}
        g = self.grupo_de.get(c["from"])
        if g is None or g.id != c["party"] or c["from"] not in g.membros:
            raise HttpError(404, "Esse grupo não existe mais.")
        if len(g.membros) >= GRUPO_MAX:
            raise HttpError(409, "O grupo encheu.")
        if g.estado == "partida":
            raise HttpError(409, "O grupo já está numa partida.")
        self._remover_do_grupo_atual(conta)
        g.membros.append(conta)
        self.grupo_de[conta] = g
        g.estado = "lobby"                 # quem entra cancela a fila
        self._mudou(g)
        return {"status": "joined", "party": self.grupo_dict(g)}

    def _remover_do_grupo_atual(self, conta: int) -> None:
        g = self.grupo_de.pop(conta, None)
        if g is None or conta not in g.membros:
            return
        g.membros.remove(conta)
        if not g.membros:
            return
        if g.lider == conta:
            g.lider = g.membros[0]
        if g.estado == "fila":
            g.estado = "lobby"
        self._mudou(g)

    def sair_do_grupo(self, conta: int) -> dict:
        self._remover_do_grupo_atual(conta)
        g = self.grupo(conta)
        self._avisar_grupo(g)
        return self.grupo_dict(g)

    def expulsar(self, conta: int, outro: int) -> dict:
        g = self.grupo(conta)
        outro = int(outro)
        if g.lider != conta:
            raise HttpError(403, "Só o líder pode remover alguém.")
        if outro not in g.membros or outro == conta:
            raise HttpError(404, "Não está no grupo.")
        self._remover_do_grupo_atual(outro)
        novo = self.grupo(outro)
        self.ev.emitir(outro, "kicked", {})
        self._avisar_grupo(novo)
        return self.grupo_dict(g)

    def promover(self, conta: int, outro: int) -> dict:
        g = self.grupo(conta)
        if g.lider != conta or int(outro) not in g.membros:
            raise HttpError(403, "Só o líder pode passar a liderança para alguém do grupo.")
        g.lider = int(outro)
        self._avisar_grupo(g)
        return self.grupo_dict(g)

    def escolher_modo(self, conta: int, modo: str) -> dict:
        g = self.grupo(conta)
        if g.lider != conta:
            raise HttpError(403, "Só o líder escolhe o modo.")
        if modo not in MODOS:
            raise HttpError(400, "Modo desconhecido.")
        if g.estado != "lobby":
            raise HttpError(409, "Cancele a busca antes de trocar o modo.")
        g.modo = modo
        self._avisar_grupo(g)
        return self.grupo_dict(g)
