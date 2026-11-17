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


COSMETICOS_JOGO = os.path.join(os.path.dirname(BACKEND), "game", "data", "cosmeticos.json")


def carregar_config(pasta: str | None = None) -> dict:
    pasta = pasta or os.path.join(BACKEND, "config")
    cfg = {"progressao": _ler(os.path.join(pasta, "progressao.json")),
           "missoes": _ler(os.path.join(pasta, "missoes.json")), "catalogo": {}, "temporadas": []}
    for arq in sorted(glob.glob(os.path.join(pasta, "catalog", "*.json"))):
        for item in _ler(arq).get("itens", []):
            cfg["catalogo"][item["id"]] = item
    for arq in sorted(glob.glob(os.path.join(pasta, "seasons", "*.json"))):
        cfg["temporadas"].append(_ler(arq))
    validar(cfg)
    return cfg


def _data(texto: str) -> float:
    return datetime.datetime.fromisoformat(texto.replace("Z", "+00:00")).timestamp()


def validar_temporada(t: dict, cfg: dict, outras=(), visuais: dict | None = None) -> list:
    """Erros de uma temporada (lista vazia = válida). Usado ao subir o servidor e por
    tools/validar_temporada.py. `visuais`: tabela de cosméticos do jogo (trajes com visual)."""
    erros = []
    for campo in ("id", "nome", "inicio", "fim", "xp_por_nivel", "recompensas"):
        if campo not in t:
            erros.append(f"falta o campo '{campo}'")
    if erros:
        return erros
    try:
        ini, fim = _data(t["inicio"]), _data(t["fim"])
        if fim <= ini:
            erros.append("'fim' deve ser depois de 'inicio'")
        for o in outras:
            if o is not t and _data(o["inicio"]) < fim and ini < _data(o["fim"]):
                erros.append(f"datas se sobrepõem à temporada {o['id']}")
    except (ValueError, TypeError, KeyError):
        erros.append("datas inválidas (use ISO 8601, ex.: 2026-11-17T00:00:00Z)")
    if not isinstance(t["xp_por_nivel"], int) or t["xp_por_nivel"] <= 0:
        erros.append("'xp_por_nivel' deve ser um inteiro positivo")
    niveis = [r.get("nivel") for r in t["recompensas"]]
    if niveis != list(range(1, len(niveis) + 1)):
        erros.append("as recompensas devem cobrir os níveis 1..N, em ordem, sem buracos nem repetição")
    vistos = set()
    for r in t["recompensas"]:
        tipos = [k for k in ("item", "faiscas") if k in r]
        if len(tipos) != 1:
            erros.append(f"nível {r.get('nivel')}: cada nível tem exatamente uma recompensa (item OU faiscas)")
            continue
        if "faiscas" in r and (not isinstance(r["faiscas"], int) or r["faiscas"] <= 0):
            erros.append(f"nível {r['nivel']}: faíscas deve ser inteiro positivo")
        if "item" in r:
            item = cfg["catalogo"].get(r["item"])
            if item is None:
                erros.append(f"nível {r['nivel']}: item '{r['item']}' não está no catálogo")
            elif r["item"] in vistos:
                erros.append(f"nível {r['nivel']}: item '{r['item']}' repetido no passe")
            elif r["item"] in cfg["progressao"]["itens_iniciais"] + cfg["progressao"].get("presentes", []):
                erros.append(f"nível {r['nivel']}: '{r['item']}' já é de todo mundo (inicial/presente)")
            elif visuais is not None and item["categoria"] == "traje" and r["item"] not in visuais.get("trajes", {}):
                erros.append(f"nível {r['nivel']}: traje '{r['item']}' não tem visual no jogo (game/data/cosmeticos.json)")
            vistos.add(r["item"])
    ids = set()
    for d in t.get("desafios", []):
        if d.get("id") in ids or d.get("tipo") not in TIPOS_MISSAO or not d.get("meta", 0) > 0 or d.get("xp", 0) < 0:
            erros.append(f"desafio inválido: {d.get('id')}")
        ids.add(d.get("id"))
    return erros


def estimar_horas(t: dict, cfg: dict) -> dict:
    """Horas de jogo até o nível máximo, pela estimativa da própria temporada."""
    e = t.get("estimativa", {})
    semanas = max(1.0, (_data(t["fim"]) - _data(t["inicio"])) / (7 * 86400))
    m = cfg["missoes"]
    media = lambda lista: sum(q["xp"] for q in lista) / max(1, len(lista))
    xp_missoes = (e.get("diarias_concluidas_por_dia", 2) * e.get("dias_jogados_por_semana", 4) * media(m["diarias"])
                  + e.get("semanais_concluidas_por_semana", 4) * media(m["semanais"])) * semanas
    xp_desafios = sum(d["xp"] for d in t.get("desafios", []))
    total = t["xp_por_nivel"] * (len(t["recompensas"]) - 1)
    resto = max(0.0, total - xp_missoes - xp_desafios)
    return {"xp_total": total, "xp_missoes": int(xp_missoes), "xp_desafios": xp_desafios, "semanas": round(semanas, 1),
            "horas": round(resto / max(1, e.get("xp_por_hora_jogando", 1000)), 1)}


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
    visuais = _ler(COSMETICOS_JOGO) if os.path.exists(COSMETICOS_JOGO) else None
    for t in cfg.get("temporadas", []):
        erros = validar_temporada(t, cfg, cfg["temporadas"], visuais)
        if erros:
            raise ValueError(f"temporada {t.get('id')}: " + "; ".join(erros))
        for d in t.get("desafios", []):
            if d["id"] in ids:
                raise ValueError(f"desafio com id repetido: {d['id']}")
            ids.add(d["id"])


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
        """As mesmas para todos: sorteio com semente pelo período. Com temporada ativa,
        os desafios dela entram como um grupo cujo período é a própria temporada."""
        m = self.cfg["missoes"]
        per = self.periodos()
        out = {"diaria": (per["diaria"], random.Random(per["diaria"][0]).sample(m["diarias"], m["diarias_por_dia"])),
               "semanal": (per["semanal"], random.Random(per["semanal"][0]).sample(m["semanais"], m["semanais_por_semana"]))}
        t = self.temporada()
        if t and t.get("desafios"):
            out["temporada"] = ((t["id"], int(_data(t["fim"]) - self.agora())), t["desafios"])
        return out

    # ---------- passe de batalha (Etapa 10) ----------
    def temporada(self) -> dict | None:
        agora = self.agora()
        for t in self.cfg.get("temporadas", []):
            if _data(t["inicio"]) <= agora < _data(t["fim"]):
                return t
        return None

    def nivel_passe(self, t: dict, xp: int) -> int:
        return min(len(t["recompensas"]), 1 + xp // t["xp_por_nivel"])

    def _recompensa_passe(self, conta: int, t: dict, n: int) -> dict | None:
        """Entrega a recompensa do nível n (deve rodar dentro de _tx). Idempotente."""
        r = t["recompensas"][n - 1]
        if "faiscas" in r:
            if self._creditar(conta, r["faiscas"], f"Passe {t['nome']}: nível {n}", f"passe:{t['id']}:{n}:{conta}"):
                return {"nivel": n, "faiscas": r["faiscas"]}
        elif "item" in r and self._desbloquear(conta, r["item"], f"passe:{t['id']}:{n}"):
            return {"nivel": n, **self.cfg["catalogo"][r["item"]]}
        return None

    def passe(self, conta: int) -> dict:
        self.garantir(conta)
        t = self.temporada()
        if t is None:
            return {"ativa": False}
        r = self.con.execute("SELECT xp FROM season_progress WHERE account_id = ? AND season_id = ?", (conta, t["id"])).fetchone()
        xp = r["xp"] if r else 0
        if r is None:
            # nível 1 vem na hora (o passe começa entregando algo)
            with self._tx():
                self.con.execute("INSERT OR IGNORE INTO season_progress VALUES (?, ?, 0, 1)", (conta, t["id"]))
                self._recompensa_passe(conta, t, 1)
        nivel = self.nivel_passe(t, xp)
        maximo = len(t["recompensas"])
        tem = {u["item_id"] for u in self.con.execute("SELECT item_id FROM unlocks WHERE account_id = ?", (conta,))}
        niveis = []
        for rec in t["recompensas"]:
            item = self.cfg["catalogo"].get(rec.get("item", ""), {})
            niveis.append({"nivel": rec["nivel"], "faiscas": rec.get("faiscas", 0), "item": rec.get("item", ""),
                           "nome": item.get("nome", ""), "raridade": item.get("raridade", ""), "categoria": item.get("categoria", ""),
                           "obtido": rec["nivel"] <= nivel and (not rec.get("item") or rec["item"] in tem)})
        return {"ativa": True, "id": t["id"], "nome": t["nome"], "termina_em_s": int(_data(t["fim"]) - self.agora()),
                "nivel": nivel, "maximo": maximo, "xp": xp, "xp_por_nivel": t["xp_por_nivel"],
                "xp_no_nivel": xp - (nivel - 1) * t["xp_por_nivel"] if nivel < maximo else t["xp_por_nivel"],
                "niveis": niveis, "desafios": self.missoes(conta).get("temporada", {}).get("quests", [])}

    def _subir_passe(self, conta: int, xp: int) -> dict | None:
        """Soma XP ao passe da temporada ativa e entrega as recompensas (dentro de _tx)."""
        t = self.temporada()
        if t is None or xp <= 0:
            return None
        r = self.con.execute("SELECT xp FROM season_progress WHERE account_id = ? AND season_id = ?", (conta, t["id"])).fetchone()
        antes = r["xp"] if r else 0
        if r is None:
            self.con.execute("INSERT INTO season_progress VALUES (?, ?, 0, 1)", (conta, t["id"]))
            self._recompensa_passe(conta, t, 1)
        n_antes, n_depois = self.nivel_passe(t, antes), self.nivel_passe(t, antes + xp)
        self.con.execute("UPDATE season_progress SET xp = ?, level = ? WHERE account_id = ? AND season_id = ?",
                         (antes + xp, n_depois, conta, t["id"]))
        entregues = [x for x in (self._recompensa_passe(conta, t, n) for n in range(n_antes + 1, n_depois + 1)) if x]
        return {"temporada": t["id"], "nome": t["nome"], "nivel_antes": n_antes, "nivel": n_depois, "xp": xp,
                "recompensas": entregues}

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
            # tetos por partida (a Ilha Ventania tem 37 baús; 16 jogadores com 100 de vida + 100 de escudo)
            for k, teto in (("baus", 40), ("coleta", 6000), ("construcoes", 800), ("dano", 4000), ("curas", 60)):
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
                            itens.append((f"{'Desafio' if grupo == 'temporada' else 'Missão'}: {q['titulo']}", q["xp"]))
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
                passe = self._subir_passe(conta, xp)
                for rec in (passe or {}).get("recompensas", []):
                    faiscas += rec.get("faiscas", 0)
                    if rec.get("id"):
                        desbloqueados.append({**rec})
                novo = self.nivel_de(antes["xp_total"] + xp)
                resumos[conta] = {"match_id": match_id, "xp": [{"motivo": m, "xp": v} for m, v in itens], "xp_total": xp,
                                  "nivel_antes": nivel_antes, "nivel": novo[0], "xp_in_level": novo[1], "xp_next": novo[2],
                                  "faiscas": faiscas, "missoes": concluidas, "desbloqueados": desbloqueados,
                                  "colocacao": j["colocacao"], "total": total, "passe": passe}
        for conta, r in resumos.items():                   # avisos só depois do COMMIT
            self.ev.emitir(conta, "progress", r)
        return {"status": "aplicado", "jogadores": len(resumos)}
