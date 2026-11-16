#!/usr/bin/env python3
"""Valida arquivos GLB contra os orçamentos do projeto. Usa só a biblioteca padrão.

Uso:
    python3 tools/assets/validate_glb.py game/assets/baus_coletaveis/bau_madeira_01.glb --categoria baus_coletaveis
    python3 tools/assets/validate_glb.py --todos      # valida todos os GLB de game/assets/<categoria>/

Checa: cabeçalho GLB, triângulos (sem colisões), materiais, tamanho das texturas
embutidas (PNG/JPEG), ossos, extensões não suportadas pela Godot (Draco, meshopt).
Código de saída 1 se houver erro.
"""

import argparse
import json
import os
import struct
import sys

RAIZ = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ORCAMENTOS = os.path.join(RAIZ, "tools", "assets", "budgets.json")
EXT_NAO_SUPORTADAS = {"KHR_draco_mesh_compression", "EXT_meshopt_compression", "KHR_mesh_quantization"}
SUFIXOS_COLISAO = ("-col", "-colonly", "-convcolonly")


def ler_glb(caminho):
    with open(caminho, "rb") as f:
        dados = f.read()
    if len(dados) < 20:
        raise ValueError("arquivo pequeno demais para ser GLB")
    magic, versao, tamanho = struct.unpack_from("<4sII", dados, 0)
    if magic != b"glTF":
        raise ValueError("não é GLB (assinatura 'glTF' ausente)")
    if versao != 2:
        raise ValueError(f"glTF versão {versao}; esperado 2")
    pos, gltf, binario = 12, None, b""
    while pos < min(tamanho, len(dados)):
        clen, ctipo = struct.unpack_from("<I4s", dados, pos)
        bloco = dados[pos + 8: pos + 8 + clen]
        if ctipo == b"JSON":
            gltf = json.loads(bloco.decode("utf-8"))
        elif ctipo == b"BIN\x00":
            binario = bloco
        pos += 8 + clen
    if gltf is None:
        raise ValueError("chunk JSON ausente")
    return gltf, binario


def tamanho_imagem(b):
    """(largura, altura) de PNG ou JPEG; None se desconhecido."""
    if b[:8] == b"\x89PNG\r\n\x1a\n":
        return struct.unpack(">II", b[16:24])
    if b[:2] == b"\xff\xd8":
        i = 2
        while i + 9 < len(b):
            if b[i] != 0xFF:
                i += 1
                continue
            marcador = b[i + 1]
            if marcador in (0xC0, 0xC1, 0xC2):
                h, w = struct.unpack(">HH", b[i + 5:i + 9])
                return w, h
            i += 2 + struct.unpack(">H", b[i + 2:i + 4])[0]
    return None


def analisar(gltf, binario):
    nos = gltf.get("nodes", [])
    malhas_colisao = {n["mesh"] for n in nos if "mesh" in n and n.get("name", "").endswith(SUFIXOS_COLISAO)}
    acessores = gltf.get("accessors", [])
    tris = 0
    for i, malha in enumerate(gltf.get("meshes", [])):
        if i in malhas_colisao:
            continue
        for prim in malha.get("primitives", []):
            if prim.get("mode", 4) != 4:  # só TRIANGLES conta
                continue
            if "indices" in prim:
                tris += acessores[prim["indices"]]["count"] // 3
            else:
                tris += acessores[prim["attributes"]["POSITION"]]["count"] // 3
    texturas = {}
    vistas = gltf.get("bufferViews", [])
    for i, img in enumerate(gltf.get("images", [])):
        nome = img.get("name", f"imagem_{i}")
        if "bufferView" in img:
            v = vistas[img["bufferView"]]
            off = v.get("byteOffset", 0)
            texturas[nome] = tamanho_imagem(binario[off: off + v["byteLength"]])
        else:
            texturas[nome] = None  # imagem externa (uri)
    ossos = max((len(s.get("joints", [])) for s in gltf.get("skins", [])), default=0)
    return {
        "tris": tris,
        "materiais": len(gltf.get("materials", [])),
        "texturas": texturas,
        "ossos": ossos,
        "animacoes": len(gltf.get("animations", [])),
        "extensoes": sorted(set(gltf.get("extensionsUsed", []))),
        "nos": [n.get("name", "") for n in nos],
    }


def validar(caminho, categoria, cfg):
    erros, avisos = [], []
    try:
        gltf, binario = ler_glb(caminho)
    except (OSError, ValueError, json.JSONDecodeError) as e:
        return [str(e)], [], {}
    st = analisar(gltf, binario)
    orc = cfg["categorias"].get(categoria)
    if orc is None:
        return [f"categoria desconhecida '{categoria}'"], [], st
    if orc["max_tris"] and st["tris"] > orc["max_tris"]:
        erros.append(f"triângulos {st['tris']} > {orc['max_tris']}")
    if st["materiais"] > orc["max_materiais"]:
        erros.append(f"materiais {st['materiais']} > {orc['max_materiais']}")
    for nome, tam in st["texturas"].items():
        if tam is None:
            avisos.append(f"textura '{nome}' externa ou de formato desconhecido; prefira embutir PNG/JPEG")
        elif max(tam) > orc["max_textura_px"]:
            erros.append(f"textura '{nome}' {tam[0]}x{tam[1]} > {orc['max_textura_px']}px")
        elif tam[0] & (tam[0] - 1) or tam[1] & (tam[1] - 1):
            avisos.append(f"textura '{nome}' {tam[0]}x{tam[1]} não é potência de 2")
    if st["ossos"] > orc["max_ossos"]:
        erros.append(f"ossos {st['ossos']} > {orc['max_ossos']}")
    if st["animacoes"] and not orc["permite_animacao"]:
        avisos.append(f"{st['animacoes']} animação(ões) em categoria estática")
    ruins = EXT_NAO_SUPORTADAS & set(st["extensoes"])
    if ruins:
        erros.append(f"extensões não suportadas pela Godot: {sorted(ruins)}")
    return erros, avisos, st


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("arquivo", nargs="?")
    p.add_argument("--categoria")
    p.add_argument("--todos", action="store_true")
    p.add_argument("--json", action="store_true", help="saída em JSON")
    a = p.parse_args()
    with open(ORCAMENTOS, encoding="utf-8") as f:
        cfg = json.load(f)

    alvos = []
    if a.todos:
        for cat in cfg["categorias"]:
            pasta = os.path.join(RAIZ, "game", "assets", cat)
            for raiz, _, arqs in os.walk(pasta):
                alvos += [(os.path.join(raiz, x), cat) for x in sorted(arqs) if x.lower().endswith(".glb")]
    elif a.arquivo and a.categoria:
        alvos = [(a.arquivo, a.categoria)]
    else:
        p.error("informe <arquivo> --categoria <cat>, ou --todos")

    falhou, relatorio = False, []
    for caminho, cat in alvos:
        erros, avisos, st = validar(caminho, cat, cfg)
        falhou |= bool(erros)
        relatorio.append({"arquivo": os.path.relpath(caminho, RAIZ), "categoria": cat, "ok": not erros,
                          "erros": erros, "avisos": avisos, "estatisticas": st})
    if a.json:
        print(json.dumps(relatorio, ensure_ascii=False, indent=2))
    else:
        if not relatorio:
            print("Nenhum GLB encontrado.")
        for r in relatorio:
            st = r["estatisticas"]
            print(f"[{'OK' if r['ok'] else 'FALHA'}] {r['arquivo']} ({r['categoria']}) "
                  f"tris={st.get('tris')} materiais={st.get('materiais')} ossos={st.get('ossos')}")
            for m in r["erros"]:
                print("   ERRO:", m)
            for m in r["avisos"]:
                print("   AVISO:", m)
    sys.exit(1 if falhou else 0)


if __name__ == "__main__":
    main()
