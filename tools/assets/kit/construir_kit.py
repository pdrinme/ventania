#!/usr/bin/env python3
"""Constrói o kit visual inicial: gera os .blend, exporta os GLB, valida e
registra no catálogo. Opcionalmente roda a importação na Godot.

Uso:
    python3 tools/assets/kit/construir_kit.py --blender-python <python-com-bpy> [--godot <godot>]
    python3 tools/assets/kit/construir_kit.py --blender <blender> [--godot <godot>]

  --blender-python  interpretador Python com o módulo bpy (ex.: .venv-bpy/bin/python)
  --blender         executável do Blender instalado (modo -b)
  --so-exportar     não regenera os .blend (útil depois de editar à mão no Blender)
"""

import argparse
import json
import os
import subprocess
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.abspath(os.path.join(AQUI, "..", "..", ".."))
sys.path.insert(0, os.path.join(RAIZ, "tools", "assets"))
import catalog  # noqa: E402

GERADORES = ["gerar_construcoes.py", "gerar_cenario.py", "gerar_bau.py", "gerar_personagem.py", "gerar_armas.py", "gerar_itens.py", "gerar_interiores.py"]


def manifesto():
    with open(os.path.join(AQUI, "kit.json"), encoding="utf-8") as f:
        return json.load(f)["assets"]


def rodar_bpy(a, script, extra=()):
    if a.blender_python:
        cmd = [a.blender_python, script, *extra]
    else:
        cmd = [a.blender, "-b", "--factory-startup", "-P", script, "--", *extra]
    r = subprocess.run(cmd, cwd=RAIZ, capture_output=True, text=True)
    saida = [l for l in (r.stdout + r.stderr).splitlines()
             if (l.startswith(("SALVO", "EXPORTADO", "ERRO ", "ERRO:", "AVISO", "ESTAT", "Traceback")) or "Error:" in l)
             and "Draco" not in l and "MeshOptimizer" not in l]
    print("\n".join("   " + l for l in saida))
    return r.returncode


def registrar(asset, estado_final):
    cat = catalog.carregar()
    item = next((x for x in cat["assets"] if x["id"] == asset["id"]), None)
    if item is None:
        item = {c: "" for c in catalog.CAMPOS}
        item.update(id=asset["id"], nome=asset["nome"], categoria=asset["categoria"], origem="original",
                    autor="Projeto Ventania", licenca="Original",
                    arquivo_fonte=f"assets_src/{asset['categoria']}/{asset['id']}.blend",
                    arquivo_exportado=f"game/assets/{asset['categoria']}/{asset['id']}.glb",
                    referencias=[], notas=asset.get("notas", ""))
        cat["assets"].append(item)
    item["estado"] = estado_final
    item["atualizado_em"] = catalog._hoje()
    erros = catalog.validar_item(item, catalog.cfg(), set())
    if erros:
        print("   ERRO catálogo:", *erros, sep="\n      ")
        return False
    catalog.salvar(cat)
    return True


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    g = p.add_mutually_exclusive_group(required=True)
    g.add_argument("--blender-python")
    g.add_argument("--blender")
    p.add_argument("--godot")
    p.add_argument("--so-exportar", action="store_true")
    a = p.parse_args()
    falhas = 0

    subprocess.run([sys.executable, os.path.join(AQUI, "gerar_paleta_png.py")], check=True)
    if not a.so_exportar:
        for ger in GERADORES:
            print("GERANDO", ger)
            falhas += rodar_bpy(a, os.path.join(AQUI, "blender", ger)) != 0

    exportador = os.path.join(RAIZ, "tools", "assets", "blender", "export_glb.py")
    exportados = []
    for asset in manifesto():
        print("EXPORTANDO", asset["id"])
        blend = os.path.join(RAIZ, "assets_src", asset["categoria"], asset["id"] + ".blend")
        extra = ["--categoria", asset["categoria"], "--id", asset["id"]]
        if a.blender_python:
            extra = ["--blend", blend, *extra]
            cmd_ok = rodar_bpy(a, exportador, extra) == 0
        else:
            r = subprocess.run([a.blender, "-b", blend, "-P", exportador, "--", *extra], cwd=RAIZ)
            cmd_ok = r.returncode == 0
        if cmd_ok:
            exportados.append(asset)
        else:
            falhas += 1

    estado = "exportado"
    if a.godot:
        print("IMPORTANDO NA GODOT")
        subprocess.run([a.godot, "--headless", "--path", "game", "--import"], cwd=RAIZ, capture_output=True)
        r = subprocess.run([a.godot, "--headless", "--path", "game", "-s", "res://tests/test_asset_import.gd"],
                           cwd=RAIZ, capture_output=True, text=True)
        print("\n".join("   " + l for l in r.stdout.splitlines() if "ASSETS_IMPORTADOS" in l or "FALHA" in l))
        print("\n".join("   " + l for l in r.stderr.splitlines() if "FALHA" in l))
        if r.returncode == 0:
            estado = "importado"
        else:
            falhas += 1

    for asset in exportados:
        falhas += not registrar(asset, estado)
    subprocess.run([sys.executable, os.path.join(RAIZ, "tools", "assets", "catalog.py"), "licencas"], cwd=RAIZ)
    print(f"KIT: {len(exportados)}/{len(manifesto())} exportados, estado '{estado}', {falhas} falha(s).")
    sys.exit(1 if falhas else 0)


if __name__ == "__main__":
    main()
