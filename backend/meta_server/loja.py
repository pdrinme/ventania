"""Loja rotativa (Etapa 11, GAME_DESIGN §9.5).

- Seções: Destaques (troca toda segunda-feira, UTC) e Diária (troca à meia-noite UTC).
- Rotação: a agenda (config/shop/agenda.json) manda quando tem entrada para o
  período; sem agenda, sorteio determinístico com semente pela data a partir do
  catálogo elegível (itens com "loja": true), sem repetir os itens da Diária dos
  últimos dias e sem repetir os Destaques da semana.
- Compra atômica: confere se o item está na loja AGORA, o preço, a posse e o
  saldo; debita no ledger e desbloqueia na mesma transação. Chave de
  idempotência do cliente: repetir o pedido não cobra duas vezes.
- Só Faíscas. Sem pagamento real.
"""
import datetime
import json
import os
import random

from .config import BACKEND
from .http import HttpError


def carregar_loja(pasta: str | None = None) -> dict:
    pasta = pasta or os.path.join(BACKEND, "config", "shop")
    with open(os.path.join(pasta, "loja.json"), encoding="utf-8") as f:
        cfg = json.load(f)
    agenda = os.path.join(pasta, "agenda.json")
    cfg["agenda"] = json.load(open(agenda, encoding="utf-8")).get("entradas", []) if os.path.exists(agenda) else []
    return cfg


def validar_loja(loja: dict, catalogo: dict, temporadas=()) -> list:
    erros = []
    elegiveis = {i for i, it in catalogo.items() if it.get("loja")}
    from .progressao import COSMETICOS_JOGO, _ler, tem_visual
    import os
    if os.path.exists(COSMETICOS_JOGO):
        visuais = _ler(COSMETICOS_JOGO)
        for i in sorted(elegiveis):
            if not tem_visual(catalogo[i], visuais):
                erros.append(f"item {i} está à venda mas não tem visual no jogo (game/data/cosmeticos.json)")
    for i in elegiveis:
        if catalogo[i]["raridade"] not in loja["precos"] and "preco" not in catalogo[i]:
            erros.append(f"item {i}: sem preço para a raridade {catalogo[i]['raridade']}")
    do_passe = {r["item"] for t in temporadas for r in t["recompensas"] if "item" in r}
    if elegiveis & do_passe:
        erros.append(f"itens do passe marcados para a loja: {sorted(elegiveis & do_passe)}")
    total = sum(s["quantidade"] for s in loja["secoes"])
    if total > len(elegiveis):
        erros.append(f"as seções pedem {total} itens, mas só há {len(elegiveis)} elegíveis")
    ids = {s["id"] for s in loja["secoes"]}
    for e in loja.get("agenda", []):
        if e.get("secao") not in ids:
            erros.append(f"agenda {e.get('data')}: seção desconhecida {e.get('secao')}")
            continue
        try:
            d = datetime.date.fromisoformat(e["data"])
        except (KeyError, ValueError):
            erros.append(f"agenda: data inválida {e.get('data')}")
            continue
        sec = next(s for s in loja["secoes"] if s["id"] == e["secao"])
        if sec["periodo"] == "semanal" and d.weekday() != 0:
            erros.append(f"agenda {e['data']}: Destaques começam na segunda-feira")
        for i in e.get("itens", []):
            if i not in elegiveis:
                erros.append(f"agenda {e['data']}: item {i} não está à venda (catálogo sem 'loja': true)")
    return erros


class Loja:
    def __init__(self, progressao, cfg: dict | None = None):
        self.p = progressao
        self.cfg = cfg or carregar_loja()
        erros = validar_loja(self.cfg, self.p.cfg["catalogo"], self.p.cfg.get("temporadas", []))
        if erros:
            raise ValueError("loja: " + "; ".join(erros))

    # ---------- rotação ----------
    def _hoje(self) -> datetime.date:
        return datetime.datetime.fromtimestamp(self.p.agora(), datetime.timezone.utc).date()

    def elegiveis(self) -> list:
        cat = self.p.cfg["catalogo"]
        ids = [i for i, it in cat.items() if it.get("loja")]
        if self.cfg.get("itens_do_passe_voltam"):
            ativa = self.p.temporada()
            for t in self.p.cfg.get("temporadas", []):
                if t is not ativa and self.p.agora() >= self.p_data(t["fim"]):
                    ids += [r["item"] for r in t["recompensas"] if "item" in r]
        return sorted(set(ids))

    @staticmethod
    def p_data(texto):
        from .progressao import _data
        return _data(texto)

    def _agenda(self, secao: str, data: datetime.date):
        for e in self.cfg["agenda"]:
            if e["secao"] == secao and e["data"] == data.isoformat():
                return list(e["itens"])
        return None

    def destaques(self, segunda: datetime.date) -> list:
        sec = self._secao("destaques")
        fixo = self._agenda("destaques", segunda)
        if fixo is not None:
            return fixo
        return sorted(random.Random(f"destaques:{segunda.isoformat()}").sample(self.elegiveis(), sec["quantidade"]))

    def diaria(self, dia: datetime.date) -> list:
        """Corrente determinística: começa 30 dias antes e anda dia a dia, excluindo os
        itens recentes (assim qualquer servidor calcula o mesmo resultado)."""
        sec = self._secao("diaria")
        sem_rep = sec.get("sem_repetir_dias", 0)
        recentes: list[list] = []
        hoje = []
        for k in range(30, -1, -1):
            d = dia - datetime.timedelta(days=k)
            segunda = d - datetime.timedelta(days=d.weekday())
            fixo = self._agenda("diaria", d)
            if fixo is not None:
                hoje = fixo
            else:
                rng = random.Random(f"diaria:{d.isoformat()}")
                pool = [i for i in self.elegiveis() if i not in set(self.destaques(segunda))]
                vistos = {i for r in recentes[-sem_rep:] for i in r} if sem_rep else set()
                # primeiro os que não apareceram nos últimos dias; se faltar, completa com os recentes
                novos = [i for i in pool if i not in vistos]
                q = min(sec["quantidade"], len(pool))
                hoje = rng.sample(novos, min(q, len(novos)))
                hoje += rng.sample([i for i in pool if i in vistos], q - len(hoje))
                hoje = sorted(hoje)
            recentes.append(hoje)
        return hoje

    def _secao(self, sid: str) -> dict:
        return next(s for s in self.cfg["secoes"] if s["id"] == sid)

    def preco(self, item: str) -> int:
        it = self.p.cfg["catalogo"][item]
        return int(it.get("preco", self.cfg["precos"][it["raridade"]]))

    def vitrine(self, dia: datetime.date | None = None) -> dict:
        """Seções atuais: itens e quando trocam (segundos)."""
        dia = dia or self._hoje()
        agora = datetime.datetime.fromtimestamp(self.p.agora(), datetime.timezone.utc)
        segunda = dia - datetime.timedelta(days=dia.weekday())
        amanha = datetime.datetime.combine(dia + datetime.timedelta(days=1), datetime.time(), datetime.timezone.utc)
        prox_seg = datetime.datetime.combine(segunda + datetime.timedelta(days=7), datetime.time(), datetime.timezone.utc)
        return {"destaques": (self.destaques(segunda), int((prox_seg - agora).total_seconds())),
                "diaria": (self.diaria(dia), int((amanha - agora).total_seconds()))}

    def loja(self, conta: int) -> dict:
        self.p.garantir(conta)
        tem = {u["item_id"] for u in self.p.con.execute("SELECT item_id FROM unlocks WHERE account_id = ?", (conta,))}
        saldo = self.p.con.execute("SELECT sparks FROM profiles WHERE account_id = ?", (conta,)).fetchone()["sparks"]
        secoes = []
        for sec in self.cfg["secoes"]:
            itens, resta = self.vitrine()[sec["id"]]
            secoes.append({"id": sec["id"], "nome": sec["nome"], "troca_em_s": resta,
                           "itens": [{**{k: v for k, v in self.p.cfg["catalogo"][i].items() if k in ("id", "nome", "categoria", "raridade", "descricao")},
                                      "preco": self.preco(i), "tem": i in tem} for i in itens]})
        return {"faiscas": saldo, "secoes": secoes}

    # ---------- compra ----------
    def comprar(self, conta: int, item: str, preco_visto, chave: str) -> dict:
        chave = str(chave or "")[:64]
        if len(chave) < 8:
            raise HttpError(400, "chave de compra obrigatória (idempotência)")
        idem = f"loja:{conta}:{chave}"
        self.p.garantir(conta)
        if self.p.con.execute("SELECT 1 FROM ledger WHERE idem_key = ?", (idem,)).fetchone():
            return {"status": "ja_comprado", "perfil": self.p.perfil(conta)}       # pedido repetido: não cobra de novo
        a_venda = {i for itens, _ in self.vitrine().values() for i in itens}
        if item not in a_venda:
            raise HttpError(409, "Esse item não está na loja agora.")
        preco = self.preco(item)
        if preco_visto is not None and int(preco_visto) != preco:
            raise HttpError(409, "O preço mudou. Abra a loja de novo.")
        nome = self.p.cfg["catalogo"][item]["nome"]
        with self.p._tx():
            if self.p.con.execute("SELECT 1 FROM unlocks WHERE account_id = ? AND item_id = ?", (conta, item)).fetchone():
                raise HttpError(409, "Você já tem esse item.")
            self.p._creditar(conta, -preco, f"Loja: {nome}", idem)            # 409 se não houver saldo
            self.p._desbloquear(conta, item, "loja")
        return {"status": "comprado", "item": item, "preco": preco, "perfil": self.p.perfil(conta)}
