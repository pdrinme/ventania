"""Administração do catálogo e da loja (Etapa 11).

Uso (na raiz do repositório):
  python3 tools/admin_loja.py listar                    # catálogo: itens, raridade, preço, origem
  python3 tools/admin_loja.py validar                   # catálogo + loja + agenda + temporadas
  python3 tools/admin_loja.py prever --dias 14          # rotação dos próximos dias (Destaques e Diária)
  python3 tools/admin_loja.py agendar --data 2026-11-23 --secao destaques --itens traje_vulcao,traje_relampago
  python3 tools/admin_loja.py desagendar --data 2026-11-23 --secao destaques
  python3 tools/admin_loja.py conceder --conta Ana --faiscas 1000 --motivo "teste da loja" [--db backend/data/meta.sqlite3]

'conceder' grava no ledger (com motivo e chave única), como qualquer outra
mudança de Faíscas; use para testes e eventos. Pode rodar com o meta-servidor
ligado (SQLite em WAL). Não existe compra com dinheiro real.
"""
import argparse
import datetime
import json
import os
import secrets
import sys
import time

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(RAIZ, "backend"))
from meta_server import config, db  # noqa: E402
from meta_server.contas import Contas  # noqa: E402
from meta_server.loja import Loja, carregar_loja, validar_loja  # noqa: E402
from meta_server.progressao import Progressao, carregar_config  # noqa: E402
from meta_server.social import Eventos  # noqa: E402

AGENDA = os.path.join(RAIZ, "backend", "config", "shop", "agenda.json")


def _loja(con=None, agora=None):
    con = con or db.connect(":memory:")
    if con is not None:
        db.migrate(con)
    p = Progressao(con, Contas(con, config.Config()), Eventos(), agora=agora)
    return Loja(p)


def listar(_a):
    cfg = carregar_config()
    loja = carregar_loja()
    passe = {r["item"]: f"passe {t['id']} nv {r['nivel']}" for t in cfg["temporadas"] for r in t["recompensas"] if "item" in r}
    p = cfg["progressao"]
    for i, it in sorted(cfg["catalogo"].items(), key=lambda x: (x[1]["categoria"], x[0])):
        origem = ("loja" if it.get("loja") else passe.get(i) or ("inicial" if i in p["itens_iniciais"] else
                  "presente" if i in p.get("presentes", []) else "nível" if any(r.get("item") == i for r in p["recompensas_nivel"].values()) else "—"))
        preco = it.get("preco", loja["precos"].get(it["raridade"])) if it.get("loja") else ""
        print(f"{i:22} {it['categoria']:9} {it['raridade']:9} {str(preco):>5}  {origem:20} {it['nome']}")


def validar(_a):
    cfg = carregar_config()           # já valida catálogo, missões e temporadas
    erros = validar_loja(carregar_loja(), cfg["catalogo"], cfg["temporadas"])
    for e in erros:
        print("ERRO:", e)
    print("loja e catálogo OK" if not erros else f"{len(erros)} erro(s)")
    return 1 if erros else 0


def prever(a):
    hoje = datetime.datetime.now(datetime.timezone.utc).date()
    loja = _loja()
    for k in range(a.dias):
        d = hoje + datetime.timedelta(days=k)
        segunda = d - datetime.timedelta(days=d.weekday())
        print(f"{d} ({'seg ter qua qui sex sáb dom'.split()[d.weekday()]})  Destaques: {', '.join(loja.destaques(segunda))}"
              f"  |  Diária: {', '.join(loja.diaria(d))}")


def _salvar_agenda(entradas):
    with open(AGENDA, encoding="utf-8") as f:
        dados = json.load(f)
    dados["entradas"] = sorted(entradas, key=lambda e: (e["data"], e["secao"]))
    with open(AGENDA, "w", encoding="utf-8") as f:
        json.dump(dados, f, ensure_ascii=False, indent=2)
        f.write("\n")


def agendar(a):
    loja = carregar_loja()
    entradas = [e for e in loja["agenda"] if not (e["data"] == a.data and e["secao"] == a.secao)]
    entradas.append({"data": a.data, "secao": a.secao, "itens": [i.strip() for i in a.itens.split(",") if i.strip()]})
    loja["agenda"] = entradas
    erros = validar_loja(loja, carregar_config()["catalogo"])
    if erros:
        for e in erros:
            print("ERRO:", e)
        return 1
    _salvar_agenda(entradas)
    print(f"agendado: {a.secao} em {a.data} (reinicie o meta-servidor para valer)")
    return 0


def desagendar(a):
    loja = carregar_loja()
    _salvar_agenda([e for e in loja["agenda"] if not (e["data"] == a.data and e["secao"] == a.secao)])
    print("removido (reinicie o meta-servidor para valer)")
    return 0


def conceder(a):
    caminho = a.db or config.load().db_abs()
    con = db.connect(caminho)
    db.migrate(con)
    p = Progressao(con, Contas(con, config.Config()), Eventos())
    conta = p.contas.por_nome(a.conta)
    if conta is None:
        print("ERRO: conta não encontrada:", a.conta)
        return 1
    p.garantir(conta)
    with p._tx():
        p._creditar(conta, a.faiscas, f"Admin: {a.motivo}", f"admin:{int(time.time())}:{secrets.token_hex(6)}")
    print(f"{a.conta}: saldo agora {p.perfil(conta)['sparks']} Faíscas")
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("listar").set_defaults(f=listar)
    sub.add_parser("validar").set_defaults(f=validar)
    pv = sub.add_parser("prever")
    pv.add_argument("--dias", type=int, default=14)
    pv.set_defaults(f=prever)
    ag = sub.add_parser("agendar")
    ag.add_argument("--data", required=True)
    ag.add_argument("--secao", required=True, choices=["destaques", "diaria"])
    ag.add_argument("--itens", required=True)
    ag.set_defaults(f=agendar)
    dg = sub.add_parser("desagendar")
    dg.add_argument("--data", required=True)
    dg.add_argument("--secao", required=True, choices=["destaques", "diaria"])
    dg.set_defaults(f=desagendar)
    cc = sub.add_parser("conceder")
    cc.add_argument("--conta", required=True)
    cc.add_argument("--faiscas", type=int, required=True)
    cc.add_argument("--motivo", required=True)
    cc.add_argument("--db")
    cc.set_defaults(f=conceder)
    a = ap.parse_args()
    sys.exit(a.f(a) or 0)


if __name__ == "__main__":
    main()
