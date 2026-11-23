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
    """Caixa de munição: lata verde com tampa de trava, alça, faixa amarela e
    cartuchos aparecendo por cima."""
    p = [
        k.caixa("caixa", (0.34, 0.22, 0.18), (0, 0, 0.09), "verde_militar", bevel=0.022),
        k.caixa("tampa", (0.35, 0.23, 0.04), (0, 0, 0.19), "metal_escuro", bevel=0.012),
        k.caixa("faixa", (0.345, 0.225, 0.05), (0, 0, 0.10), "amarelo_sol", bevel=0.005),
        k.caixa("trava", (0.05, 0.03, 0.07), (0.12, -0.12, 0.17), "metal_claro", bevel=0.008),
        k.caixa("alca", (0.12, 0.025, 0.02), (0, 0, 0.225), "preto", bevel=0.006),
    ]
    for i in range(4):
        x = -0.13 + i * 0.04
        p.append(k.cilindro("cartucho", 0.013, 0.06, (x, 0.07, 0.235), "dourado", lados=8))
        p.append(k.esfera("ponta", 0.013, (x, 0.07, 0.268), "coral", segmentos=6, aneis=4))
    o = k.unir(p, "municao_01")
    k.marcador("mao", (0, 0, 0.10), pai=o)   # onde a mão segura


def curativo_01():
    """Rolo de atadura com uma fita solta e um alfinete."""
    p = [
        k.cilindro("rolo", 0.07, 0.12, (0, 0, 0.07), "branco", lados=14, rot=(0, 90, 0)),
        k.cilindro("miolo", 0.03, 0.125, (0, 0, 0.07), "pele_1", lados=8, rot=(0, 90, 0)),
        k.cilindro("listra", 0.071, 0.02, (0, 0, 0.07), "coral", lados=14, rot=(0, 90, 0)),
        k.caixa("ponta", (0.10, 0.12, 0.012), (0, -0.09, 0.005), "branco", rot=(4, 0, 6)),
        k.caixa("alfinete", (0.04, 0.008, 0.008), (0.02, -0.12, 0.014), "metal_claro"),
    ]
    o = k.unir(p, "curativo_01")
    k.marcador("mao", (0, 0, 0.07), pai=o)   # onde a mão segura


def kit_cura_01():
    """Maleta de cura: branca e redonda, com fechos, alça e o coração do jogo."""
    p = [
        k.caixa("maleta", (0.36, 0.26, 0.16), (0, 0, 0.08), "branco", bevel=0.035),
        k.caixa("emenda", (0.365, 0.265, 0.015), (0, 0, 0.11), "cinza_tecido"),
        k.caixa("alca", (0.14, 0.03, 0.05), (0, 0, 0.18), "cinza_tecido", bevel=0.01),
        k.caixa("fecho_e", (0.04, 0.02, 0.05), (-0.12, -0.13, 0.11), "metal_claro", bevel=0.006),
        k.caixa("fecho_d", (0.04, 0.02, 0.05), (0.12, -0.13, 0.11), "metal_claro", bevel=0.006),
        # coração (símbolo próprio do jogo para cura)
        k.esfera("coracao_e", 0.04, (-0.025, -0.135, 0.07), "coral", escala=(1, 0.4, 1), segmentos=8, aneis=6),
        k.esfera("coracao_d", 0.04, (0.025, -0.135, 0.07), "coral", escala=(1, 0.4, 1), segmentos=8, aneis=6),
        k.caixa("coracao_ponta", (0.055, 0.02, 0.055), (0, -0.133, 0.04), "coral", rot=(0, 45, 0)),
        k.esfera("brilho", 0.012, (-0.035, -0.15, 0.085), "branco", segmentos=5, aneis=3),
    ]
    o = k.unir(p, "kit_cura_01")
    k.marcador("mao", (0, 0, 0.18), pai=o)   # onde a mão segura


def _celula(nome, r, h, faixa):
    p = [
        k.cilindro("vidro", r, h, (0, 0, h / 2 + 0.02), "azul_ceu", lados=12),
        k.cilindro("liquido", r * 0.8, h * 0.85, (0, 0, h / 2 + 0.02), "lente", lados=10),
        k.cilindro("tampa_b", r * 1.1, 0.03 + r * 0.1, (0, 0, 0.015), "metal_escuro", lados=12),
        k.cilindro("tampa_t", r * 1.1, 0.03 + r * 0.1, (0, 0, h + 0.03), "metal_escuro", lados=12),
        k.cilindro("bico", r * 0.4, 0.03, (0, 0, h + 0.06), "metal_claro", lados=8),
        k.esfera("bolha", r * 0.16, (r * 0.35, -r * 0.5, h * 0.6), "branco", segmentos=6, aneis=4),
    ]
    for a in range(3):
        import math
        ang = a * math.tau / 3
        p.append(k.caixa("haste", (0.012, 0.012, h), (math.cos(ang) * r * 1.02, math.sin(ang) * r * 1.02, h / 2 + 0.02), "metal_escuro"))
    if faixa:
        p.append(k.cilindro("faixa", r * 1.04, 0.03, (0, 0, h / 2 + 0.02), "teal", lados=12))
    o = k.unir(p, nome)
    return o


def celula_escudo_p_01():
    o = _celula("celula_escudo_p_01", 0.05, 0.14, False)
    k.marcador("mao", (0, 0, 0.09), pai=o)   # onde a mão segura


def celula_escudo_g_01():
    o = _celula("celula_escudo_g_01", 0.09, 0.26, True)
    k.marcador("mao", (0, 0, 0.16), pai=o)   # onde a mão segura


GERADORES = {f.__name__: f for f in (municao_01, curativo_01, kit_cura_01, celula_escudo_p_01, celula_escudo_g_01)}


def main():
    for asset_id in sys.argv[1:] or list(GERADORES):
        k.nova_cena()
        GERADORES[asset_id]()
        k.salvar("baus_coletaveis", asset_id)


if __name__ == "__main__":
    main()
