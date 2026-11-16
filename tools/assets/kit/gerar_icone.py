#!/usr/bin/env python3
"""Gera o ícone do jogo (256x256): círculo azul-petróleo com redemoinho amarelo. Só stdlib.
Uso: python3 tools/assets/kit/gerar_icone.py  ->  game/assets/ui/icone.png
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gerar_paleta_png import RAIZ, png  # noqa: E402

N = 256
TEAL, ESCURO, AMARELO, CORAL = (34, 184, 168), (22, 124, 132), (255, 201, 60), (255, 107, 91)


def main():
    linhas = []
    c = (N - 1) / 2
    for y in range(N):
        linha = []
        for x in range(N):
            dx, dy = x - c, y - c
            r = math.hypot(dx, dy)
            ang = math.atan2(dy, dx)
            cor = (0, 0, 0)
            if r < 124:
                cor = ESCURO if r > 112 else TEAL
                # espiral de Arquimedes: r = a + b*theta (duas voltas)
                for volta in range(3):
                    alvo = 18 + 14.5 * ((ang + math.pi) + 2 * math.pi * volta)
                    if abs(r - alvo) < 7 and alvo < 104:
                        cor = AMARELO
                if r < 11:
                    cor = CORAL
            linha += cor
        linhas.append(linha)
    saida = os.path.join(RAIZ, "game", "assets", "ui", "icone.png")
    png(saida, N, N, linhas)
    print("ICONE:", os.path.relpath(saida, RAIZ))


if __name__ == "__main__":
    main()
