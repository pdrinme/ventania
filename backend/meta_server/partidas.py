"""Servidores de partida, matchmaking, salas privadas e tickets (ARCHITECTURE §6).

- Cada sala de um servidor dedicado se anuncia com POST /v1/servers/heartbeat
  (a cada ~2 s), com o segredo compartilhado no cabeçalho X-Ventania-Server.
  Informa porta, modo, estado da partida, humanos, máximo e as contas presentes.
  A resposta traz ordens para a sala: se é privada e se deve começar já.
- Fila: o líder põe o grupo na fila; a cada segundo, cada grupo da fila vai para
  a sala pública em espera, do mesmo modo e com vagas, que tiver mais gente
  (as vagas ficam reservadas por 90 s). Os bots completam a partida.
- Ticket: cada integrante recebe um ticket assinado (HMAC-SHA256 com o segredo)
  com conta, nome, porta da sala e validade. O servidor de partida confere o
  ticket no HELLO e usa o nome dele: o cliente não escolhe quem é.
- Sala privada: o líder reserva uma sala vazia e recebe um código; amigos entram
  com o código; o dono manda começar quando quiser.
"""
import base64
import hashlib
import hmac
import json
import secrets
import time

from .http import HttpError

SALA_VIVA_S = 10.0
RESERVA_S = 90.0
CODIGO_LETRAS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"   # sem 0/O, 1/I
ESTADOS = ("espera", "contagem", "onibus", "jogo", "fim", "treino")


def assinar(segredo: str, dados: dict) -> str:
    corpo = base64.b64encode(json.dumps(dados, separators=(",", ":"), ensure_ascii=False).encode("utf-8")).decode("ascii")
    sig = hmac.new(segredo.encode("utf-8"), corpo.encode("ascii"), hashlib.sha256).hexdigest()
    return corpo + "." + sig


def verificar(segredo: str, ticket: str) -> dict | None:
    """Usado nos testes (o servidor de partida faz o mesmo em GDScript)."""
    try:
        corpo, sig = ticket.split(".", 1)
    except ValueError:
        return None
    esperado = hmac.new(segredo.encode("utf-8"), corpo.encode("ascii"), hashlib.sha256).hexdigest()
    if not hmac.compare_digest(sig, esperado):
        return None
    dados = json.loads(base64.b64decode(corpo))
    return dados if dados.get("exp", 0) >= time.time() else None


class Sala:
    def __init__(self, chave: str):
        self.chave = chave
        self.host = ""
        self.port = 0
        self.modo = "br"
        self.estado = "espera"
        self.humanos = 0
        self.max = 16
        self.presentes: set[int] = set()
        self.reservas: dict[int, float] = {}     # conta -> expira (monotonic)
        self.visto = 0.0
        self.codigo = ""                         # sala privada
        self.dono = 0
        self.privada_desde = 0.0
        self.iniciar = False

    def viva(self) -> bool:
        return time.monotonic() - self.visto < SALA_VIVA_S

    def vagas(self) -> int:
        pendentes = [c for c in self.reservas if c not in self.presentes]
        return self.max - self.humanos - len(pendentes)

    def publica(self) -> dict:
        return {"host": self.host, "port": self.port, "mode": self.modo, "state": self.estado,
                "humans": self.humanos, "max": self.max, "private": bool(self.codigo)}


class Partidas:
    def __init__(self, social, contas, segredo: str, ticket_ttl_s: int = 120):
        self.social = social
        self.contas = contas
        self.ev = social.ev
        self.segredo = segredo
        self.ticket_ttl_s = ticket_ttl_s
        self.salas: dict[str, Sala] = {}
        self.fila: list = []                     # grupos, por ordem de chegada
        self.traje_de = lambda conta: ""         # App liga à progressão (cosmético vai no ticket)
        social.ao_mudar_grupo = self._grupo_mudou

    # ---------- servidores ----------
    def heartbeat(self, segredo_recebido: str, ip: str, d: dict) -> dict:
        if not self.segredo or not hmac.compare_digest(segredo_recebido or "", self.segredo):
            raise HttpError(403, "Segredo do servidor inválido.")
        try:
            porta = int(d["port"])
        except (KeyError, TypeError, ValueError):
            raise HttpError(400, "porta obrigatória")
        host = str(d.get("host") or ip)
        chave = f"{host}:{porta}"
        s = self.salas.get(chave) or Sala(chave)
        self.salas[chave] = s
        s.host, s.port = host, porta
        s.modo = d.get("mode", "br") if d.get("mode") in ("br", "treino") else "br"
        s.estado = d.get("state") if d.get("state") in ESTADOS else "espera"
        s.humanos = max(0, int(d.get("humans", 0)))
        s.max = max(1, int(d.get("max", 16)))
        s.presentes = {int(x) for x in d.get("accounts", []) if str(x).isdigit()}
        s.visto = time.monotonic()
        agora = time.monotonic()
        s.reservas = {c: t for c, t in s.reservas.items() if t > agora and c not in s.presentes}
        # sala privada: libera quando esvazia
        if s.codigo and s.humanos == 0 and not s.reservas and agora - s.privada_desde > 30.0:
            s.codigo, s.dono, s.iniciar = "", 0, False
        resp = {"private": bool(s.codigo), "start": s.iniciar}
        if s.iniciar and s.estado != "espera":
            s.iniciar = False
        self.combinar()
        return resp

    def lista_salas(self) -> list:
        return [s.publica() for s in self.salas.values() if s.viva()]

    # ---------- tickets ----------
    def ticket(self, conta: int, sala: Sala) -> str:
        return assinar(self.segredo, {"acc": conta, "name": self.contas.nome(conta), "port": sala.port,
                                      "priv": bool(sala.codigo), "traje": self.traje_de(conta),
                                      "exp": int(time.time()) + self.ticket_ttl_s, "n": secrets.token_hex(4)})

    def _enviar_para_sala(self, g, sala: Sala) -> None:
        agora = time.monotonic()
        for m in g.membros:
            sala.reservas[m] = agora + RESERVA_S
        g.estado = "partida"
        g.partida = {"host": sala.host, "port": sala.port, "mode": sala.modo, "private_code": sala.codigo}
        for m in g.membros:
            self.ev.emitir(m, "match_found", {**g.partida, "ticket": self.ticket(m, sala)})
        self.social._avisar_grupo(g)

    # ---------- fila ----------
    def entrar_na_fila(self, conta: int) -> dict:
        g = self.social.grupo(conta)
        if g.lider != conta:
            raise HttpError(403, "Só o líder começa a busca.")
        if g.estado == "partida":
            raise HttpError(409, "O grupo já está numa partida.")
        if g.estado != "fila":
            g.estado = "fila"
            g.fila_desde = time.monotonic()
            self.fila.append(g)
            self.social._avisar_grupo(g)
        self.combinar()
        return self.social.grupo_dict(g)

    def cancelar_fila(self, conta: int) -> dict:
        g = self.social.grupo(conta)
        if g.estado == "fila":
            g.estado = "lobby"
            self._tirar_da_fila(g)
            self.social._avisar_grupo(g)
        return self.social.grupo_dict(g)

    def voltou_ao_lobby(self, conta: int) -> dict:
        g = self.social.grupo(conta)
        if g.estado == "partida":
            g.estado = "lobby"
            g.partida = None
            self.social._avisar_grupo(g)
        return self.social.grupo_dict(g)

    def _tirar_da_fila(self, g) -> None:
        if g in self.fila:
            self.fila.remove(g)

    def _grupo_mudou(self, g) -> None:
        if g.estado != "fila":
            self._tirar_da_fila(g)

    def combinar(self) -> None:
        for g in list(self.fila):
            if g.estado != "fila" or not g.membros:
                self._tirar_da_fila(g)
                continue
            candidatas = [s for s in self.salas.values()
                          if s.viva() and not s.codigo and s.modo == g.modo
                          and (s.estado == "espera" or s.modo == "treino") and s.vagas() >= len(g.membros)]
            if not candidatas:
                continue
            sala = max(candidatas, key=lambda s: (s.max - s.vagas(), -s.port))
            self._tirar_da_fila(g)
            self._enviar_para_sala(g, sala)

    # ---------- sala privada ----------
    def criar_privada(self, conta: int) -> dict:
        g = self.social.grupo(conta)
        if g.lider != conta:
            raise HttpError(403, "Só o líder cria a sala privada.")
        livres = [s for s in self.salas.values() if s.viva() and not s.codigo and s.modo == g.modo
                  and s.humanos == 0 and not s.reservas and s.estado in ("espera", "treino")]
        if not livres:
            raise HttpError(409, "Nenhuma sala livre agora. Tente de novo em instantes.")
        sala = min(livres, key=lambda s: s.port)
        usados = {s.codigo for s in self.salas.values()}
        codigo = ""
        while not codigo or codigo in usados:
            codigo = "".join(secrets.choice(CODIGO_LETRAS) for _ in range(5))
        sala.codigo, sala.dono, sala.privada_desde, sala.iniciar = codigo, conta, time.monotonic(), False
        self._tirar_da_fila(g)
        self._enviar_para_sala(g, sala)
        return {"code": codigo, **sala.publica()}

    def entrar_privada(self, conta: int, codigo: str) -> dict:
        codigo = (codigo or "").strip().upper()
        sala = next((s for s in self.salas.values() if s.codigo and s.codigo == codigo and s.viva()), None)
        if sala is None:
            raise HttpError(404, "Código não encontrado.")
        g = self.social.grupo(conta)
        if g.lider != conta:
            raise HttpError(403, "Só o líder do grupo entra com o código.")
        if sala.vagas() < len(g.membros):
            raise HttpError(409, "A sala está cheia.")
        if sala.estado not in ("espera", "treino"):
            raise HttpError(409, "A partida dessa sala já começou.")
        self._tirar_da_fila(g)
        self._enviar_para_sala(g, sala)
        return {"code": codigo, **sala.publica()}

    def iniciar_privada(self, conta: int) -> dict:
        sala = next((s for s in self.salas.values() if s.codigo and s.dono == conta), None)
        if sala is None:
            raise HttpError(404, "Você não é dono de uma sala privada.")
        sala.iniciar = True
        return {"code": sala.codigo, "start": True}
