#!/usr/bin/env python3
"""Catálogo de assets do projeto (assets_catalog.json). Só biblioteca padrão.

Comandos:
    python3 tools/assets/catalog.py validar          # valida o catálogo inteiro (usar em CI)
    python3 tools/assets/catalog.py listar [--categoria X] [--estado Y]
    python3 tools/assets/catalog.py novo --id bau_madeira_01 --nome "Baú de madeira" \
        --categoria baus_coletaveis --origem original --autor "Fulano" --licenca Original
    python3 tools/assets/catalog.py estado <id> <novo_estado>
    python3 tools/assets/catalog.py licencas          # regenera game/assets/<cat>/LICENSES.json

Regras de validação:
  - id único, minúsculo, [a-z0-9_]; categoria e estado conhecidos;
  - origem e licença dentro das listas permitidas (budgets.json);
  - terceiros_licenciado exige url_origem e, para CC-BY, texto de atribuição;
  - a partir de "exportado", o GLB precisa existir e passar no validate_glb.py;
  - estados só avançam um passo por vez via comando `estado` (pode voltar livremente).
"""

import argparse
import datetime
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
import validate_glb  # noqa: E402

RAIZ = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
CATALOGO = os.path.join(RAIZ, "assets_catalog.json")
ORCAMENTOS = os.path.join(RAIZ, "tools", "assets", "budgets.json")

ESTADOS = ["planejado", "blockout", "modelado", "texturizado", "exportado", "importado", "otimizado", "aprovado"]
ID_RE = re.compile(r"^[a-z0-9]+(_[a-z0-9]+)*$")
CAMPOS = ["id", "nome", "categoria", "origem", "autor", "licenca", "url_origem", "atribuicao",
          "arquivo_fonte", "arquivo_exportado", "estado", "referencias", "notas", "atualizado_em"]


def carregar():
    with open(CATALOGO, encoding="utf-8") as f:
        return json.load(f)


def salvar(cat):
    tmp = CATALOGO + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(cat, f, ensure_ascii=False, indent=2)
        f.write("\n")
    os.replace(tmp, CATALOGO)


def cfg():
    with open(ORCAMENTOS, encoding="utf-8") as f:
        return json.load(f)


def validar_item(it, c, ids):
    e = []
    iid = it.get("id", "?")
    for campo in ("id", "nome", "categoria", "origem", "autor", "licenca", "estado"):
        if not it.get(campo):
            e.append(f"{iid}: campo obrigatório '{campo}' vazio")
    if iid in ids:
        e.append(f"{iid}: id duplicado")
    ids.add(iid)
    if not ID_RE.match(iid):
        e.append(f"{iid}: id inválido (use minúsculas, números e _)")
    if it.get("categoria") not in c["categorias"]:
        e.append(f"{iid}: categoria desconhecida '{it.get('categoria')}'")
    if it.get("estado") not in ESTADOS:
        e.append(f"{iid}: estado desconhecido '{it.get('estado')}'")
    if it.get("origem") not in c["origens_permitidas"]:
        e.append(f"{iid}: origem '{it.get('origem')}' não permitida ({c['origens_permitidas']})")
    if it.get("licenca") not in c["licencas_permitidas"]:
        e.append(f"{iid}: licença '{it.get('licenca')}' não permitida ({c['licencas_permitidas']})")
    if it.get("origem") == "original" and it.get("licenca") != "Original":
        e.append(f"{iid}: origem 'original' deve usar licença 'Original'")
    if it.get("origem") == "terceiros_licenciado":
        if not it.get("url_origem"):
            e.append(f"{iid}: terceiros_licenciado exige url_origem")
        if it.get("licenca", "").startswith("CC-BY") and not it.get("atribuicao"):
            e.append(f"{iid}: licença CC-BY exige texto de atribuição")
    fonte = it.get("arquivo_fonte")
    if fonte and not os.path.exists(os.path.join(RAIZ, fonte)):
        e.append(f"{iid}: arquivo_fonte não encontrado: {fonte}")
    if it.get("estado") in ESTADOS and ESTADOS.index(it["estado"]) >= ESTADOS.index("exportado"):
        glb = it.get("arquivo_exportado")
        if not glb or not os.path.exists(os.path.join(RAIZ, glb)):
            e.append(f"{iid}: estado '{it['estado']}' exige arquivo_exportado existente")
        elif glb.endswith(".glb") and it.get("categoria") in c["categorias"]:
            erros_glb, _, _ = validate_glb.validar(os.path.join(RAIZ, glb), it["categoria"], c)
            e += [f"{iid}: GLB: {m}" for m in erros_glb]
    return e


def cmd_validar(_a):
    c, cat = cfg(), carregar()
    erros, ids = [], set()
    for it in cat["assets"]:
        erros += validar_item(it, c, ids)
    for m in erros:
        print("ERRO:", m)
    print(f"{len(cat['assets'])} asset(s), {len(erros)} erro(s).")
    return 1 if erros else 0


def cmd_listar(a):
    for it in carregar()["assets"]:
        if a.categoria and it["categoria"] != a.categoria:
            continue
        if a.estado and it["estado"] != a.estado:
            continue
        print(f"{it['id']:<28} {it['categoria']:<20} {it['estado']:<12} {it['licenca']:<10} {it['nome']}")
    return 0


def _hoje():
    return datetime.date.today().isoformat()


def cmd_novo(a):
    cat = carregar()
    it = {k: "" for k in CAMPOS}
    it.update(id=a.id, nome=a.nome, categoria=a.categoria, origem=a.origem, autor=a.autor,
              licenca=a.licenca, url_origem=a.url_origem or "", atribuicao=a.atribuicao or "",
              arquivo_fonte=f"assets_src/{a.categoria}/{a.id}.blend",
              arquivo_exportado=f"game/assets/{a.categoria}/{a.id}.glb",
              estado="planejado", referencias=[], atualizado_em=_hoje())
    # na criação o .blend ainda não existe; validamos o resto
    tmp = dict(it, arquivo_fonte="")
    erros = validar_item(tmp, cfg(), {x["id"] for x in cat["assets"]})
    if erros:
        for m in erros:
            print("ERRO:", m)
        return 1
    cat["assets"].append(it)
    salvar(cat)
    print("Adicionado:", a.id)
    return 0


def cmd_estado(a):
    cat = carregar()
    if a.estado not in ESTADOS:
        print("ERRO: estados válidos:", ", ".join(ESTADOS))
        return 1
    for it in cat["assets"]:
        if it["id"] == a.id:
            atual, novo = ESTADOS.index(it["estado"]), ESTADOS.index(a.estado)
            if novo > atual + 1:
                print(f"ERRO: avance um passo por vez ({it['estado']} -> {ESTADOS[atual + 1]})")
                return 1
            antigo = it["estado"]
            it["estado"], it["atualizado_em"] = a.estado, _hoje()
            erros = validar_item(it, cfg(), set())
            if erros:
                it["estado"] = antigo
                for m in erros:
                    print("ERRO:", m)
                return 1
            salvar(cat)
            print(f"{a.id}: {antigo} -> {a.estado}")
            return 0
    print("ERRO: id não encontrado:", a.id)
    return 1


def cmd_licencas(_a):
    c, cat = cfg(), carregar()
    for categoria in c["categorias"]:
        entradas = [{
            "file": os.path.basename(it["arquivo_exportado"]),
            "asset_id": it["id"], "author": it["autor"],
            "source": it["url_origem"] or "original", "license": it["licenca"],
            "attribution": it["atribuicao"],
        } for it in cat["assets"]
            if it["categoria"] == categoria and it["arquivo_exportado"]
            and os.path.exists(os.path.join(RAIZ, it["arquivo_exportado"]))]
        caminho = os.path.join(RAIZ, "game", "assets", categoria, "LICENSES.json")
        with open(caminho, "w", encoding="utf-8") as f:
            json.dump(entradas, f, ensure_ascii=False, indent=2)
            f.write("\n")
    print("LICENSES.json regenerados.")
    return 0


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    s = p.add_subparsers(dest="cmd", required=True)
    s.add_parser("validar").set_defaults(f=cmd_validar)
    l_ = s.add_parser("listar")
    l_.add_argument("--categoria")
    l_.add_argument("--estado")
    l_.set_defaults(f=cmd_listar)
    n = s.add_parser("novo")
    for campo in ("id", "nome", "categoria", "origem", "autor", "licenca"):
        n.add_argument(f"--{campo}", required=True)
    n.add_argument("--url-origem", dest="url_origem")
    n.add_argument("--atribuicao")
    n.set_defaults(f=cmd_novo)
    e = s.add_parser("estado")
    e.add_argument("id")
    e.add_argument("estado")
    e.set_defaults(f=cmd_estado)
    s.add_parser("licencas").set_defaults(f=cmd_licencas)
    a = p.parse_args()
    sys.exit(a.f(a))


if __name__ == "__main__":
    main()
