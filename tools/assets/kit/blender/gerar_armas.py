"""Gera as armas do Ventania (designs originais, estilo do kit: blocos arredondados,
cores da paleta). O cano aponta para -Y no Blender (vira +Z na Godot).
Origem no punho (onde a mão segura).

  rajada_01   fuzil de assalto (corpo teal, carregador curvo)
  trovao_01   escopeta (cano duplo grosso, coronha de madeira)
  zumbido_01  submetralhadora (compacta, carregador em tambor)
  faisca_01   pistola (pequena, cano curto)
  gaviao_01   fuzil de precisão (longo, luneta)
  picareta_01 picareta permanente (ferramenta de coleta; cabo para +Z, ponta para -Y)

Uso: python tools/assets/kit/blender/gerar_armas.py [id ...]
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kit_comum as k  # noqa: E402


# Marcadores (posição no Blender; origem da arma = empunhadura da mão direita):
#   grip_r: centro da mão direita no punho     grip_l: apoio da mão esquerda
#   muzzle: saída do cano                       mag: carregador (recarga)
MARCADORES = {
    "rajada_01":  {"grip_r": (0, 0.0, -0.03), "grip_l": (0, -0.36, 0.01), "muzzle": (0, -0.65, 0.07), "mag": (0, -0.17, -0.10)},
    "trovao_01":  {"grip_r": (0, 0.02, -0.03), "grip_l": (0, -0.33, -0.01), "muzzle": (0, -0.63, 0.08), "mag": (0, -0.10, 0.03)},
    "zumbido_01": {"grip_r": (0, 0.03, -0.03), "grip_l": (0, -0.19, 0.02), "muzzle": (0, -0.36, 0.07), "mag": (0, -0.10, -0.06)},
    "faisca_01":  {"grip_r": (0, 0.0, -0.01), "grip_l": (0.025, 0.02, -0.06), "muzzle": (0, -0.22, 0.075), "mag": (0, 0.0, -0.08)},
    "gaviao_01":  {"grip_r": (0, 0.02, -0.03), "grip_l": (0, -0.30, 0.02), "muzzle": (0, -0.85, 0.07), "mag": (0, -0.14, -0.06)},
    # picareta: cabo vertical (+Z), cabeça no alto; "cabeca" = ponto de impacto da ponta
    "picareta_01": {"grip_r": (0, 0.0, 0.0), "grip_l": (0, 0.0, 0.20), "cabeca": (0, -0.31, 0.55), "centro_cabeca": (0, 0.0, 0.60)},
}


def _base(partes, asset_id):
    o = k.unir(partes, asset_id)
    o["tipo"] = "arma"
    for nome, pos in MARCADORES[asset_id].items():
        k.marcador(nome, pos, pai=o)
    return o
    return o


def rajada_01():
    p = [
        k.caixa("corpo", (0.09, 0.42, 0.12), (0, -0.12, 0.05), "teal_escuro", bevel=0.015),
        k.caixa("topo", (0.07, 0.30, 0.03), (0, -0.14, 0.125), "metal_escuro"),
        k.cilindro("cano", 0.022, 0.32, (0, -0.48, 0.07), "metal_escuro", lados=8, rot=(90, 0, 0)),
        k.caixa("guarda_mao", (0.08, 0.18, 0.08), (0, -0.38, 0.06), "teal", bevel=0.015),
        k.caixa("punho", (0.06, 0.07, 0.13), (0, 0.0, -0.05), "preto", bevel=0.01, rot=(-15, 0, 0)),
        k.caixa("carregador", (0.05, 0.08, 0.16), (0, -0.16, -0.07), "metal_escuro", bevel=0.01, rot=(18, 0, 0)),
        k.caixa("coronha", (0.07, 0.22, 0.11), (0, 0.17, 0.03), "teal", bevel=0.02),
        k.caixa("faixa", (0.092, 0.05, 0.122), (0, -0.25, 0.05), "amarelo_sol"),
    ]
    _base(p, "rajada_01")


def trovao_01():
    p = [
        k.caixa("corpo", (0.10, 0.22, 0.12), (0, -0.08, 0.05), "metal_escuro", bevel=0.015),
        k.cilindro("cano_e", 0.032, 0.44, (-0.025, -0.40, 0.08), "metal_claro", lados=10, rot=(90, 0, 0)),
        k.cilindro("cano_d", 0.032, 0.44, (0.025, -0.40, 0.08), "metal_claro", lados=10, rot=(90, 0, 0)),
        k.caixa("bomba", (0.09, 0.14, 0.06), (0, -0.33, 0.02), "madeira_media", bevel=0.015),
        k.caixa("punho", (0.06, 0.07, 0.12), (0, 0.02, -0.05), "madeira_escura", bevel=0.01, rot=(-20, 0, 0)),
        k.caixa("coronha", (0.08, 0.26, 0.13), (0, 0.17, 0.02), "madeira_media", bevel=0.02, rot=(8, 0, 0)),
        k.caixa("faixa", (0.102, 0.04, 0.122), (0, -0.16, 0.05), "coral"),
    ]
    _base(p, "trovao_01")


def zumbido_01():
    p = [
        k.caixa("corpo", (0.09, 0.28, 0.11), (0, -0.08, 0.05), "roxo", bevel=0.015),
        k.cilindro("cano", 0.02, 0.14, (0, -0.28, 0.07), "metal_escuro", lados=8, rot=(90, 0, 0)),
        k.cilindro("tambor", 0.07, 0.06, (0, -0.10, -0.04), "metal_escuro", lados=12, rot=(0, 90, 0)),
        k.caixa("punho", (0.055, 0.06, 0.12), (0, 0.03, -0.05), "preto", bevel=0.01, rot=(-15, 0, 0)),
        k.caixa("alca", (0.03, 0.12, 0.03), (0, -0.10, 0.125), "metal_escuro"),
        k.caixa("faixa", (0.092, 0.04, 0.112), (0, -0.18, 0.05), "amarelo_sol"),
    ]
    _base(p, "zumbido_01")


def faisca_01():
    p = [
        k.caixa("ferrolho", (0.05, 0.20, 0.06), (0, -0.07, 0.07), "laranja", bevel=0.012),
        k.cilindro("cano", 0.014, 0.05, (0, -0.19, 0.075), "metal_escuro", lados=8, rot=(90, 0, 0)),
        k.caixa("punho", (0.045, 0.065, 0.13), (0, 0.0, -0.02), "preto", bevel=0.01, rot=(-12, 0, 0)),
        k.caixa("gatilho", (0.03, 0.04, 0.03), (0, -0.05, 0.015), "metal_escuro"),
    ]
    _base(p, "faisca_01")


def gaviao_01():
    p = [
        k.caixa("corpo", (0.08, 0.40, 0.11), (0, -0.10, 0.05), "verde_militar", bevel=0.015),
        k.cilindro("cano", 0.02, 0.55, (0, -0.57, 0.07), "metal_escuro", lados=8, rot=(90, 0, 0)),
        k.cilindro("luneta", 0.035, 0.24, (0, -0.12, 0.16), "preto", lados=10, rot=(90, 0, 0)),
        k.cilindro("lente", 0.03, 0.01, (0, -0.245, 0.16), "lente", lados=10, rot=(90, 0, 0)),
        k.caixa("suporte", (0.03, 0.10, 0.04), (0, -0.12, 0.12), "metal_escuro"),
        k.caixa("punho", (0.055, 0.065, 0.12), (0, 0.02, -0.05), "preto", bevel=0.01, rot=(-15, 0, 0)),
        k.caixa("carregador", (0.05, 0.07, 0.09), (0, -0.14, -0.03), "metal_escuro", bevel=0.01),
        k.caixa("coronha", (0.07, 0.26, 0.12), (0, 0.19, 0.03), "verde_militar", bevel=0.02),
        k.caixa("faixa", (0.082, 0.04, 0.112), (0, -0.28, 0.05), "amarelo_sol"),
    ]
    _base(p, "gaviao_01")


def picareta_01():
    """Picareta Ventania: cabo de madeira com empunhadura teal enrolada, cabeça de
    metal com ponta curva para a frente e martelo curto atrás, anel amarelo de vento.
    Variações cosméticas futuras: outro GLB com os mesmos marcadores."""
    p = [
        k.cilindro("cabo", 0.024, 0.78, (0, 0, 0.25), "madeira_media", lados=8),
        k.cilindro("empunhadura", 0.031, 0.22, (0, 0, -0.01), "teal", lados=8),
        k.toro("fita_1", 0.031, 0.008, (0, 0, 0.09), "teal_escuro", seg=8, seg_menor=4),
        k.toro("fita_2", 0.031, 0.008, (0, 0, -0.11), "teal_escuro", seg=8, seg_menor=4),
        k.esfera("pomo", 0.038, (0, 0, -0.16), "metal_escuro", segmentos=8, aneis=5),
        k.caixa("colar", (0.075, 0.11, 0.12), (0, 0, 0.60), "metal_escuro", bevel=0.015),
        k.cilindro("ponta", 0.046, 0.27, (0, -0.18, 0.585), "metal_claro", lados=8, rot=(100, 0, 0), raio_topo=0.006),
        k.cilindro("martelo", 0.042, 0.15, (0, 0.125, 0.60), "metal_claro", lados=8, rot=(-90, 0, 0), raio_topo=0.03),
        k.caixa("face_martelo", (0.07, 0.025, 0.07), (0, 0.205, 0.60), "metal_escuro", bevel=0.008),
        k.toro("anel_vento", 0.05, 0.012, (0, 0, 0.60), "amarelo_sol", rot=(0, 90, 0), seg=12, seg_menor=4),
        k.caixa("topo", (0.05, 0.05, 0.04), (0, 0, 0.675), "amarelo_sol", bevel=0.01),
    ]
    o = _base(p, "picareta_01")
    o["tipo"] = "ferramenta"


GERADORES = {f.__name__: f for f in (rajada_01, trovao_01, zumbido_01, faisca_01, gaviao_01, picareta_01)}


def main():
    for asset_id in sys.argv[1:] or list(GERADORES):
        k.nova_cena()
        GERADORES[asset_id]()
        k.salvar("armas", asset_id)


if __name__ == "__main__":
    main()
