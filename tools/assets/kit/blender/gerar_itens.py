"""Gera itens coletáveis originais: munição e consumíveis.

  municao_01          caixa de munição (faixa amarela)
  curativo_01         rolo de atadura (+vida pequena)
  kit_cura_01         maleta com coração coral (+vida grande)
  celula_escudo_p_01  cápsula azul pequena (+escudo pequeno)
  celula_escudo_g_01  cilindro azul grande (+escudo grande)

Uso: python tools/assets/kit/blender/gerar_itens.py [id ...]
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kit_comum as k  # noqa: E402


def municao_01():
    p = [
        k.caixa("caixa", (0.34, 0.22, 0.18), (0, 0, 0.09), "verde_militar", bevel=0.02),
        k.caixa("tampa", (0.35, 0.23, 0.04), (0, 0, 0.19), "metal_escuro", bevel=0.01),
        k.caixa("faixa", (0.345, 0.225, 0.05), (0, 0, 0.10), "amarelo_sol"),
    ]
    o = k.unir(p, "municao_01")
    k.marcador("mao", (0, 0, 0.10), pai=o)   # onde a mão segura


def curativo_01():
    p = [
        k.cilindro("rolo", 0.07, 0.12, (0, 0, 0.07), "branco", lados=12, rot=(0, 90, 0)),
        k.cilindro("miolo", 0.03, 0.125, (0, 0, 0.07), "pele_1", lados=8, rot=(0, 90, 0)),
        k.caixa("ponta", (0.10, 0.12, 0.012), (0, -0.09, 0.005), "branco"),
    ]
    o = k.unir(p, "curativo_01")
    k.marcador("mao", (0, 0, 0.07), pai=o)   # onde a mão segura


def kit_cura_01():
    p = [
        k.caixa("maleta", (0.36, 0.26, 0.16), (0, 0, 0.08), "branco", bevel=0.025),
        k.caixa("alca", (0.14, 0.03, 0.05), (0, 0, 0.18), "cinza_tecido"),
        # coração (símbolo próprio do jogo para cura)
        k.esfera("coracao_e", 0.04, (-0.025, -0.135, 0.10), "coral", escala=(1, 0.4, 1), segmentos=8, aneis=6),
        k.esfera("coracao_d", 0.04, (0.025, -0.135, 0.10), "coral", escala=(1, 0.4, 1), segmentos=8, aneis=6),
        k.caixa("coracao_ponta", (0.055, 0.02, 0.055), (0, -0.133, 0.07), "coral", rot=(0, 45, 0)),
    ]
    o = k.unir(p, "kit_cura_01")
    k.marcador("mao", (0, 0, 0.18), pai=o)   # onde a mão segura


def celula_escudo_p_01():
    p = [
        k.cilindro("vidro", 0.05, 0.14, (0, 0, 0.09), "azul_ceu", lados=10),
        k.cilindro("tampa_b", 0.055, 0.03, (0, 0, 0.015), "metal_escuro", lados=10),
        k.cilindro("tampa_t", 0.055, 0.03, (0, 0, 0.17), "metal_escuro", lados=10),
    ]
    o = k.unir(p, "celula_escudo_p_01")
    k.marcador("mao", (0, 0, 0.09), pai=o)   # onde a mão segura


def celula_escudo_g_01():
    p = [
        k.cilindro("vidro", 0.09, 0.26, (0, 0, 0.16), "azul_ceu", lados=12),
        k.cilindro("tampa_b", 0.10, 0.04, (0, 0, 0.02), "metal_escuro", lados=12),
        k.cilindro("tampa_t", 0.10, 0.04, (0, 0, 0.30), "metal_escuro", lados=12),
        k.caixa("faixa", (0.19, 0.19, 0.03), (0, 0, 0.16), "teal", rot=(0, 0, 45)),
    ]
    o = k.unir(p, "celula_escudo_g_01")
    k.marcador("mao", (0, 0, 0.16), pai=o)   # onde a mão segura


GERADORES = {f.__name__: f for f in (municao_01, curativo_01, kit_cura_01, celula_escudo_p_01, celula_escudo_g_01)}


def main():
    for asset_id in sys.argv[1:] or list(GERADORES):
        k.nova_cena()
        GERADORES[asset_id]()
        k.salvar("baus_coletaveis", asset_id)


if __name__ == "__main__":
    main()
