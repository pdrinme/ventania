"""Progressão (Etapa 9): XP, nível, missões, Faíscas com ledger, desbloqueios e equipados.

Regras (ARCHITECTURE §6):
- Só o meta-servidor concede XP, Faíscas e itens. O cliente nunca envia "ganhei X".
- O XP vem do relatório que o servidor de partida envia no fim de cada Battle
  Royale, autenticado pelo segredo compartilhado. Cada partida é aplicada uma
  única vez (chave: match_id).
- Toda mudança de Faíscas entra no ledger com uma chave de idempotência única,
  na mesma transação que muda o saldo. O saldo nunca fica negativo.
- Configuração em backend/config/progressao.json, missoes.json e catalog/*.json.
"""
import datetime
import glob
import json
import os
import random
import time
from contextlib import contextmanager

from .config import BACKEND
from .http import HttpError

TIPOS_MISSAO = ("partidas", "eliminacoes", "baus", "minutos_vivo", "top10", "vitorias", "coleta", "construcoes", "dano", "curas")
CATEGORIAS = ("traje", "picareta", "planador", "emote", "mochila", "acessorio")


def _ler(caminho: str) -> dict:
    with open(caminho, encoding="utf-8") as f:
        return json.load(f)


def carregar_config(pasta: str | None = None) -> dict:
    pasta = pasta or os.path.join(BACKEND, "config")
    cfg = {"progressao": _ler(os.path.join(pasta, "progressao.json")),
           "missoes": _ler(os.path.join(pasta, "missoes.json")), "catalogo": {}}
    for arq in sorted(glob.glob(os.path.join(pasta, "catalog", "*.json"))):
        for item in _ler(arq).get("itens", []):
            cfg["catalogo"][item["id"]] = item
    validar(cfg)
    return cfg


def validar(cfg: dict) -> None:
    """Configuração inválida impede o servidor de subir (ARCHITECTURE §5)."""
    p, m, cat = cfg["progressao"], cfg["missoes"], cfg["catalogo"]
    for item in cat.values():
        if item.get("categoria") not in CATEGORIAS:
            raise ValueError(f"item {item.get('id')}: categoria inválida {item.get('categoria')}")
    for i in p["itens_iniciais"] + p.get("presentes", []):
        if i not in cat:
            raise ValueError(f"item inicial/presente {i} não está no catálogo")
    for slot, i in p["equipados_iniciais"].items():
        if i not in p["itens_iniciais"] or cat[i]["categoria"] != slot:
            raise ValueError(f"equipado inicial inválido: {slot}={i}")
    for nivel, r in p["recompensas_nivel"].items():
        if not str(nivel).isdigit() or ("item" in r and r["item"] not in cat):
            raise ValueError(f"recompensa de nível inválida: {nivel}")
    ids = set()
    for grupo in ("diarias", "semanais"):
        for q in m[grupo]:
            if q["id"] in ids or q["tipo"] not in TIPOS_MISSAO or q["meta"] <= 0:
                raise ValueError(f"missão inválida: {q}")
            ids.add(q["id"])
    if len(m["diarias"]) < m["diarias_por_dia"] or len(m["semanais"]) < m["semanais_por_semana"]:
        raise ValueError("poucas missões no pool")


class Progressao:
    def __init__(self, con, contas, eventos, cfg: dict | None = None, agora=None):
        self.con = con
        self.contas = contas
        self.ev = eventos
        self.cfg = cfg or carregar_config()
        self.agora = agora or time.time           # injetável nos testes (troca de dia/semana)

    @contextmanager
    def _tx(self):
        self.con.execute("BEGIN IMMEDIATE")
        try:
            yield
            self.con.execute("COMMIT")
        except Exception:
            self.con.execute("ROLLBACK")
            raise

    # ---------- níveis ----------
    def xp_do_nivel(self, n: int) -> int:
        c = self.cfg["progressao"]["niveis"]
        return min(c["teto"], c["base"] + c["passo"] * (n - 1))

    def nivel_de(self, xp_total: int) -> tuple[int, int, int]:
        """(nível, xp dentro do nível, xp para o próximo)."""
        n, resto = 1, xp_total
        maximo = self.cfg["progressao"]["niveis"]["maximo"]
        while n < maximo and resto >= self.xp_do_nivel(n):
            resto -= self.xp_do_nivel(n)
            n += 1
        return n, resto, self.xp_do_nivel(n)

    # ---------- perfil ----------
    def garantir(self, conta: int) -> None:
        """Cria o perfil com os itens iniciais e entrega os presentes (idempotente)."""
        p = self.cfg["progressao"]
        agora = int(self.agora())
        if self.con.execute("SELECT 1 FROM profiles WHERE account_id = ?", (conta,)).fetchone():
            faltam = [i for i in p.get("presentes", []) if not self.con.execute(
                "SELECT 1 FROM unlocks WHERE account_id = ? AND item_id = ?", (conta, i)).fetchone()]
            for item in faltam:
                self.con.execute("INSERT OR IGNORE INTO unlocks VALUES (?, ?, 'presente', ?)", (conta, item, agora))
            return
        with self._tx():
            self.con.execute("INSERT OR IGNORE INTO profiles (account_id) VALUES (?)", (conta,))
            for item in p["itens_iniciais"]:
                self.con.execute("INSERT OR IGNORE INTO unlocks VALUES (?, ?, 'inicial', ?)", (conta, item, agora))
            for item in p.get("presentes", []):
                self.con.execute("INSERT OR IGNORE INTO unlocks VALUES (?, ?, 'presente', ?)", (conta, item, agora))
            for slot, item in p["equipados_iniciais"].items():
                self.con.execute("INSERT OR IGNORE INTO loadout VALUES (?, ?, ?)", (conta, slot, item))

    def equipado(self, conta: int, slot: str) -> str:
        r = self.con.execute("SELECT item_id FROM loadout WHERE account_id = ? AND slot = ?", (conta, slot)).fetchone()
        return r["item_id"] if r else self.cfg["progressao"]["equipados_iniciais"].get(slot, "")

    def perfil(self, conta: int) -> dict:
        self.garantir(conta)
        r = self.con.execute("SELECT * FROM profiles WHERE account_id = ?", (conta,)).fetchone()
        nivel, no_nivel, proximo = self.nivel_de(r["xp_total"])
        desbloq = [{"item": u["item_id"], "source": u["source"], "at": u["created_at"],
                    **{k: v for k, v in self.cfg["catalogo"].get(u["item_id"], {}).items() if k in ("nome", "categoria", "raridade", "descricao")}}
                   for u in self.con.execute("SELECT * FROM unlocks WHERE account_id = ? ORDER BY created_at, item_id", (conta,))]
        equip = {l["slot"]: l["item_id"] for l in self.con.execute("SELECT * FROM loadout WHERE account_id = ?", (conta,))}
        return {"level": nivel, "xp_in_level": no_nivel, "xp_next": proximo, "xp_total": r["xp_total"],
                "sparks": r["sparks"], "matches": r["matches"], "wins": r["wins"], "kills": r["kills"],
                "unlocks": desbloq, "equipped": equip}

    def equipar(self, conta: int, slot: str, item: str) -> dict:
        self.garantir(conta)
        info = self.cfg["catalogo"].get(item)
        if info is None or info["categoria"] != slot:
            raise HttpError(400, "Esse item não serve nesse espaço.")
        if not self.con.execute("SELECT 1 FROM unlocks WHERE account_id = ? AND item_id = ?", (conta, item)).fetchone():
            raise HttpError(403, "Você ainda não tem esse item.")
        self.con.execute("INSERT OR REPLACE INTO loadout VALUES (?, ?, ?)", (conta, slot, item))
        return self.perfil(conta)

    def ledger(self, conta: int, limite: int = 30) -> list:
        return [dict(r) for r in self.con.execute(
            "SELECT delta, balance_after, reason, created_at FROM ledger WHERE account_id = ? ORDER BY id DESC LIMIT ?",
            (conta, max(1, min(limite, 200))))]

    def historico(self, conta: int, limite: int = 10) -> list:
        return [{**{k: r[k] for k in ("match_id", "placement", "kills", "time_alive_s", "xp", "sparks")},
                 "total": r["total"], "at": r["received_at"]}
                for r in self.con.execute(
                    "SELECT r.*, m.total, m.received_at FROM match_results r JOIN match_reports m USING (match_id) "
                    "WHERE r.account_id = ? ORDER BY m.received_at DESC LIMIT ?", (conta, max(1, min(limite, 50))))]

    # ---------- Faíscas ----------
    def _creditar(self, conta: int, delta: int, motivo: str, chave: str) -> bool:
        """Muda o saldo e registra no ledger (deve rodar dentro de _tx). False se a chave já foi usada."""
        if delta == 0 or self.con.execute("SELECT 1 FROM ledger WHERE idem_key = ?", (chave,)).fetchone():
            return False
        saldo = self.con.execute("SELECT sparks FROM profiles WHERE account_id = ?", (conta,)).fetchone()["sparks"]
        if saldo + delta < 0:
            raise HttpError(409, "Faíscas insuficientes.")
        self.con.execute("UPDATE profiles SET sparks = ? WHERE account_id = ?", (saldo + delta, conta))
        self.con.execute("INSERT INTO ledger (account_id, delta, balance_after, reason, idem_key, created_at) VALUES (?, ?, ?, ?, ?, ?)",
                         (conta, delta, saldo + delta, motivo, chave, int(self.agora())))
        return True

    def _desbloquear(self, conta: int, item: str, origem: str) -> bool:
        cur = self.con.execute("INSERT OR IGNORE INTO unlocks VALUES (?, ?, ?, ?)", (conta, item, origem, int(self.agora())))
        return cur.rowcount > 0

    # ---------- missões ----------
    def periodos(self) -> dict:
        agora = datetime.datetime.fromtimestamp(self.agora(), datetime.timezone.utc)
        ano, semana, _ = agora.isocalendar()
        amanha = (agora + datetime.timedelta(days=1)).replace(hour=0, minute=0, second=0, microsecond=0)
        prox_seg = (agora + datetime.timedelta(days=7 - agora.weekday())).replace(hour=0, minute=0, second=0, microsecond=0)
        return {"diaria": (f"d{agora:%Y-%m-%d}", int((amanha - agora).total_seconds())),
                "semanal": (f"s{ano}-W{semana:02d}", int((prox_seg - agora).total_seconds()))}

    def ativas(self) -> dict:
        """As mesmas para todos: sorteio com semente pelo período."""
        m = self.cfg["missoes"]
        per = self.periodos()
        return {"diaria": (per["diaria"], random.Random(per["diaria"][0]).sample(m["diarias"], m["diarias_por_dia"])),
                "semanal": (per["semanal"], random.Random(per["semanal"][0]).sample(m["semanais"], m["semanais_por_semana"]))}

    def missoes(self, conta: int) -> dict:
        out = {}
        for grupo, ((periodo, resta), lista) in self.ativas().items():
            itens = []
            for q in lista:
                r = self.con.execute("SELECT progress, completed_at FROM quest_progress WHERE account_id = ? AND quest_id = ? AND period = ?",
                                     (conta, q["id"], periodo)).fetchone()
                itens.append({**q, "progresso": min(q["meta"], r["progress"] if r else 0),
                              "concluida": bool(r and r["completed_at"])})
            out[grupo] = {"period": periodo, "ends_in_s": resta, "quests": itens}
        return out

    # ---------- relatório de partida ----------
    def _xp_partida(self, j: dict, total: int) -> list:
        x = self.cfg["progressao"]["xp"]
        itens = [("Participação", x["participacao"])]
        minutos = min(x["minutos_max"], j["tempo_s"] // 60)
        if minutos:
            itens.append((f"Tempo vivo ({minutos} min)", minutos * x["por_minuto_vivo"]))
        elims = min(x["eliminacoes_max"], j["eliminacoes"])
        if elims:
            itens.append((f"Eliminações ({elims})", elims * x["por_eliminacao"]))
        col = j["colocacao"]
        if col == 1 and j["venceu"]:
            itens.append(("Vitória!", x["vitoria"]))
        if 0 < col <= 5 and total > 5:
            itens.append(("Entre os 5 melhores", x["top5"]))
        elif 0 < col <= 10 and total > 10:
            itens.append(("Entre os 10 melhores", x["top10"]))
        baus = min(x["baus_max"], j["baus"])
        if baus:
            itens.append((f"Baús abertos ({baus})", baus * x["por_bau"]))
        coleta = min(x["coleta_xp_max"], j["coleta"] // x["coleta_por_xp"])
        if coleta:
            itens.append(("Coleta de materiais", coleta))
        constr = min(x["construcoes_xp_max"], j["construcoes"] // x["construcoes_por_xp"])
        if constr:
            itens.append(("Construções", constr))
        return itens

    @staticmethod
    def _limpar_jogador(j: dict, total: int) -> dict | None:
        """Números plausíveis (o relatório é autenticado, mas um bug não deve virar XP infinito)."""
        try:
            acc = int(j["acc"])
            out = {"acc": acc, "colocacao": max(0, min(total, int(j.get("colocacao", 0)))),
                   "eliminacoes": max(0, min(total - 1, int(j.get("eliminacoes", 0)))),
                   "tempo_s": max(0, min(3600, int(j.get("tempo_s", 0)))),
                   "venceu": bool(j.get("venceu", False)) and int(j.get("colocacao", 0)) == 1}
            for k, teto in (("baus", 200), ("coleta", 20000), ("construcoes", 3000), ("dano", 50000), ("curas", 200)):
                out[k] = max(0, min(teto, int(j.get(k, 0))))
            return out if acc > 0 else None
        except (KeyError, TypeError, ValueError):
            return None

    def aplicar_relatorio(self, d: dict, sala: str) -> dict:
        try:
            match_id = str(d["match_id"])[:80]
            total = max(1, min(100, int(d.get("total", 1))))
        except (KeyError, TypeError, ValueError):
            raise HttpError(400, "relatório inválido")
        if d.get("mode", "br") != "br":
            return {"status": "ignorado", "motivo": "só partidas de Battle Royale dão XP"}
        if self.con.execute("SELECT 1 FROM match_reports WHERE match_id = ?", (match_id,)).fetchone():
            return {"status": "repetido"}          # idempotência: aplicado uma única vez
        jogadores = [x for x in (self._limpar_jogador(j, total) for j in d.get("players", [])) if x]
        jogadores = [j for j in jogadores if self.con.execute("SELECT 1 FROM accounts WHERE id = ?", (j["acc"],)).fetchone()]
        for j in jogadores:
            self.garantir(j["acc"])
        ativas = self.ativas()
        resumos = {}
        agora = int(self.agora())
        with self._tx():
            self.con.execute("INSERT INTO match_reports VALUES (?, ?, 'br', ?, ?)", (match_id, sala, total, agora))
            for j in jogadores:
                conta = j["acc"]
                antes = self.con.execute("SELECT * FROM profiles WHERE account_id = ?", (conta,)).fetchone()
                itens = self._xp_partida(j, total)
                # missões: contagens desta partida
                cont = {"partidas": 1, "eliminacoes": j["eliminacoes"], "baus": j["baus"], "minutos_vivo": j["tempo_s"] // 60,
                        "top10": 1 if 0 < j["colocacao"] <= 10 else 0, "vitorias": 1 if j["venceu"] else 0,
                        "coleta": j["coleta"], "construcoes": j["construcoes"], "dano": j["dano"], "curas": j["curas"]}
                concluidas = []
                faiscas = 0
                for grupo, ((periodo, _), lista) in ativas.items():
                    for q in lista:
                        n = cont.get(q["tipo"], 0)
                        if n <= 0:
                            continue
                        r = self.con.execute("SELECT progress, completed_at FROM quest_progress WHERE account_id = ? AND quest_id = ? AND period = ?",
                                             (conta, q["id"], periodo)).fetchone()
                        if r and r["completed_at"]:
                            continue
                        prog = min(q["meta"], (r["progress"] if r else 0) + n)
                        feito = prog >= q["meta"]
                        self.con.execute("INSERT OR REPLACE INTO quest_progress VALUES (?, ?, ?, ?, ?)",
                                         (conta, q["id"], periodo, prog, agora if feito else None))
                        if feito:
                            concluidas.append({"id": q["id"], "titulo": q["titulo"], "xp": q["xp"], "faiscas": q["faiscas"]})
                            itens.append((f"Missão: {q['titulo']}", q["xp"]))
                            if self._creditar(conta, q["faiscas"], f"Missão: {q['titulo']}", f"missao:{q['id']}:{periodo}:{conta}"):
                                faiscas += q["faiscas"]
                xp = sum(v for _, v in itens)
                nivel_antes = self.nivel_de(antes["xp_total"])[0]
                nivel_depois = self.nivel_de(antes["xp_total"] + xp)[0]
                desbloqueados = []
                p = self.cfg["progressao"]
                for n in range(nivel_antes + 1, nivel_depois + 1):
                    if self._creditar(conta, p["faiscas_por_nivel"], f"Nível {n}", f"nivel:{n}:{conta}"):
                        faiscas += p["faiscas_por_nivel"]
                    r = p["recompensas_nivel"].get(str(n), {})
                    if r.get("faiscas") and self._creditar(conta, r["faiscas"], f"Recompensa do nível {n}", f"nivel_bonus:{n}:{conta}"):
                        faiscas += r["faiscas"]
                    if r.get("item") and self._desbloquear(conta, r["item"], f"nivel:{n}"):
                        desbloqueados.append({**self.cfg["catalogo"][r["item"]], "nivel": n})
                self.con.execute("UPDATE profiles SET xp_total = xp_total + ?, level = ?, matches = matches + 1, "
                                 "wins = wins + ?, kills = kills + ? WHERE account_id = ?",
                                 (xp, nivel_depois, 1 if j["venceu"] else 0, j["eliminacoes"], conta))
                self.con.execute("INSERT INTO match_results VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                                 (match_id, conta, j["colocacao"], j["eliminacoes"], j["tempo_s"], xp, faiscas,
                                  json.dumps({"xp": itens}, ensure_ascii=False)))
                novo = self.nivel_de(antes["xp_total"] + xp)
                resumos[conta] = {"match_id": match_id, "xp": [{"motivo": m, "xp": v} for m, v in itens], "xp_total": xp,
                                  "nivel_antes": nivel_antes, "nivel": novo[0], "xp_in_level": novo[1], "xp_next": novo[2],
                                  "faiscas": faiscas, "missoes": concluidas, "desbloqueados": desbloqueados,
                                  "colocacao": j["colocacao"], "total": total}
        for conta, r in resumos.items():                   # avisos só depois do COMMIT
            self.ev.emitir(conta, "progress", r)
        return {"status": "aplicado", "jogadores": len(resumos)}
