#!/usr/bin/env python3
"""Gera o atlas de paleta (PNG 256x256) a partir de paleta.json. Só biblioteca padrão.

Uso: python3 tools/assets/kit/gerar_paleta_png.py
Saída: game/assets/texturas_materiais/paleta_ventania.png
"""
import json
import os
import struct
import zlib

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.abspath(os.path.join(AQUI, "..", "..", ".."))
SAIDA = os.path.join(RAIZ, "game", "assets", "texturas_materiais", "paleta_ventania.png")


def carregar():
    with open(os.path.join(AQUI, "paleta.json"), encoding="utf-8") as f:
        return json.load(f)


def hex_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def png(caminho, w, h, linhas):
    def bloco(tipo, dados):
        return struct.pack(">I", len(dados)) + tipo + dados + struct.pack(">I", zlib.crc32(tipo + dados) & 0xFFFFFFFF)
    bruto = b"".join(b"\x00" + bytes(l) for l in linhas)
    with open(caminho, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + bloco(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                + bloco(b"IDAT", zlib.compress(bruto, 9)) + bloco(b"IEND", b""))


def main():
    p = carregar()
    n, c = p["atlas_px"], p["celula_px"]
    por_linha = n // c
    if len(p["cores"]) > por_linha * por_linha:
        raise SystemExit("paleta maior que o atlas")
    nomes = [x[0] for x in p["cores"]]
    if len(set(nomes)) != len(nomes):
        raise SystemExit("nomes de cor duplicados")
    fundo = (255, 0, 255)  # células vazias em magenta: erro de UV fica visível
    linhas = []
    for y in range(n):
        linha = []
        for x in range(n):
            i = (y // c) * por_linha + x // c
            linha += hex_rgb(p["cores"][i][1]) if i < len(p["cores"]) else fundo
        linhas.append(linha)
    os.makedirs(os.path.dirname(SAIDA), exist_ok=True)
    png(SAIDA, n, n, linhas)
    print("PALETA:", os.path.relpath(SAIDA, RAIZ), f"({len(nomes)} cores)")


if __name__ == "__main__":
    main()
