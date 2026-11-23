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


def _guarda(y, z, cor="metal_escuro", r=0.035):
    """Guarda-mato (aro do gatilho) + gatilho."""
    return [k.toro("guarda", r, 0.007, (0, y, z), cor, rot=(0, 90, 0), seg=10, seg_menor=4),
            k.caixa("gatilho", (0.012, 0.012, 0.03), (0, y + 0.005, z + 0.005), "metal_escuro", rot=(-15, 0, 0))]


def _miras(y0, y1, z, cor="metal_escuro", alta=0.03):
    """Alça de mira atrás (dois dentes) e massa na frente."""
    return [k.caixa("alca_e", (0.012, 0.02, alta), (-0.016, y0, z + alta / 2), cor),
            k.caixa("alca_d", (0.012, 0.02, alta), (0.016, y0, z + alta / 2), cor),
            k.caixa("massa", (0.01, 0.02, alta * 1.1), (0, y1, z + alta * 0.55), cor)]


def _quebra_chama(y, z, r, cor="metal_escuro"):
    return [k.cilindro("freio", r * 1.45, 0.06, (0, y, z), cor, lados=8, rot=(90, 0, 0)),
            k.toro("freio_anel", r * 1.45, 0.006, (0, y - 0.025, z), "metal_claro", rot=(90, 0, 0), seg=8, seg_menor=4)]


def _riscas(y, z, n, larg, cor):
    """Ranhuras de borracha no punho."""
    return [k.caixa("risca", (larg, 0.072, 0.008), (0, y, z - i * 0.022), cor, rot=(-15, 0, 0)) for i in range(n)]


def rajada_01():
    """Fuzil de assalto: corpo teal arredondado, guarda-mão vazado, carregador curvo
    em dois gomos, coronha esqueleto, mira de trilho."""
    p = [
        k.caixa("corpo", (0.09, 0.40, 0.12), (0, -0.12, 0.05), "teal_escuro", bevel=0.022),
        k.caixa("tampa", (0.075, 0.30, 0.03), (0, -0.13, 0.12), "metal_escuro", bevel=0.008),
        k.caixa("janela", (0.092, 0.08, 0.035), (0, -0.04, 0.07), "preto", bevel=0.008),
        k.cilindro("cano", 0.02, 0.30, (0, -0.49, 0.07), "metal_escuro", lados=10, rot=(90, 0, 0)),
        k.caixa("guarda_mao", (0.084, 0.20, 0.085), (0, -0.39, 0.06), "teal", bevel=0.02),
        k.caixa("furo1", (0.086, 0.035, 0.03), (0, -0.34, 0.075), "teal_escuro", bevel=0.01),
        k.caixa("furo2", (0.086, 0.035, 0.03), (0, -0.42, 0.075), "teal_escuro", bevel=0.01),
        k.caixa("punho", (0.058, 0.07, 0.13), (0, 0.0, -0.05), "preto", bevel=0.014, rot=(-15, 0, 0)),
        k.caixa("carregador", (0.05, 0.075, 0.09), (0, -0.155, -0.05), "metal_escuro", bevel=0.012, rot=(10, 0, 0)),
        k.caixa("carregador2", (0.048, 0.072, 0.08), (0, -0.18, -0.13), "metal_escuro", bevel=0.012, rot=(24, 0, 0)),
        k.caixa("base_carreg", (0.056, 0.082, 0.018), (0, -0.2, -0.17), "amarelo_sol", bevel=0.005, rot=(24, 0, 0)),
        k.caixa("coronha_sup", (0.065, 0.24, 0.04), (0, 0.18, 0.08), "teal", bevel=0.015),
        k.caixa("coronha_inf", (0.065, 0.2, 0.035), (0, 0.2, -0.01), "teal", bevel=0.015, rot=(-10, 0, 0)),
        k.caixa("soleira", (0.07, 0.04, 0.13), (0, 0.3, 0.035), "preto", bevel=0.015),
        k.caixa("faixa", (0.093, 0.04, 0.123), (0, -0.25, 0.05), "amarelo_sol", bevel=0.005),
    ] + _guarda(-0.04, -0.005) + _miras(0.0, -0.36, 0.135) + _quebra_chama(-0.645, 0.07, 0.02) + _riscas(0.0, -0.03, 4, 0.062, "cinza_tecido")
    _base(p, "rajada_01")


def trovao_01():
    """Escopeta de cano duplo: canos grossos com anéis, bomba de madeira com
    sulcos, coronha curva de madeira com placa de borracha, faixa coral."""
    p = [
        k.caixa("corpo", (0.10, 0.22, 0.12), (0, -0.08, 0.05), "metal_escuro", bevel=0.02),
        k.caixa("placa_lado", (0.104, 0.12, 0.07), (0, -0.07, 0.05), "metal_claro", bevel=0.01),
        k.cilindro("cano_e", 0.032, 0.44, (-0.026, -0.40, 0.08), "metal_claro", lados=12, rot=(90, 0, 0)),
        k.cilindro("cano_d", 0.032, 0.44, (0.026, -0.40, 0.08), "metal_claro", lados=12, rot=(90, 0, 0)),
        k.cilindro("boca_e", 0.036, 0.04, (-0.026, -0.61, 0.08), "metal_escuro", lados=12, rot=(90, 0, 0)),
        k.cilindro("boca_d", 0.036, 0.04, (0.026, -0.61, 0.08), "metal_escuro", lados=12, rot=(90, 0, 0)),
        k.caixa("costela", (0.012, 0.42, 0.012), (0, -0.4, 0.117), "metal_escuro"),
        k.esfera("mira", 0.008, (0, -0.6, 0.125), "amarelo_sol", segmentos=6, aneis=4),
        k.caixa("bomba", (0.092, 0.15, 0.065), (0, -0.33, 0.02), "madeira_media", bevel=0.02),
    ] + [k.caixa("sulco", (0.094, 0.01, 0.067), (0, -0.28 - i * 0.03, 0.02), "madeira_escura") for i in range(4)] + [
        k.caixa("punho", (0.06, 0.07, 0.12), (0, 0.02, -0.05), "madeira_escura", bevel=0.014, rot=(-20, 0, 0)),
        k.caixa("coronha", (0.08, 0.26, 0.12), (0, 0.17, 0.02), "madeira_media", bevel=0.03, rot=(8, 0, 0)),
        k.caixa("soleira", (0.084, 0.03, 0.135), (0, 0.3, 0.0), "preto", bevel=0.012, rot=(8, 0, 0)),
        k.caixa("faixa", (0.104, 0.04, 0.124), (0, -0.16, 0.05), "coral", bevel=0.005),
    ] + _guarda(-0.03, -0.005)
    _base(p, "trovao_01")


def zumbido_01():
    """Submetralhadora: compacta e redonda, tambor com janelinha, alça de
    transporte com mira, cano com camisa furada, coronha retrátil de arame."""
    p = [
        k.caixa("corpo", (0.09, 0.28, 0.11), (0, -0.08, 0.05), "roxo", bevel=0.025),
        k.cilindro("camisa", 0.03, 0.12, (0, -0.27, 0.07), "metal_escuro", lados=10, rot=(90, 0, 0)),
    ] + [k.caixa("furo", (0.062, 0.012, 0.02), (0, -0.23 - i * 0.03, 0.07), "preto") for i in range(3)] + [
        k.cilindro("cano", 0.016, 0.06, (0, -0.35, 0.07), "metal_escuro", lados=8, rot=(90, 0, 0)),
        k.cilindro("tambor", 0.072, 0.064, (0, -0.10, -0.045), "metal_escuro", lados=16, rot=(0, 90, 0)),
        k.cilindro("tampa_tambor", 0.05, 0.068, (0, -0.10, -0.045), "amarelo_sol", lados=12, rot=(0, 90, 0)),
        k.caixa("punho", (0.055, 0.06, 0.12), (0, 0.03, -0.05), "preto", bevel=0.012, rot=(-15, 0, 0)),
        k.caixa("alca", (0.03, 0.14, 0.025), (0, -0.10, 0.135), "metal_escuro", bevel=0.006),
        k.caixa("alca_pe1", (0.025, 0.02, 0.03), (0, -0.04, 0.115), "metal_escuro"),
        k.caixa("alca_pe2", (0.025, 0.02, 0.03), (0, -0.16, 0.115), "metal_escuro"),
        k.caixa("arame_e", (0.008, 0.16, 0.008), (-0.03, 0.14, 0.06), "metal_claro"),
        k.caixa("arame_d", (0.008, 0.16, 0.008), (0.03, 0.14, 0.06), "metal_claro"),
        k.caixa("soleira", (0.07, 0.02, 0.06), (0, 0.22, 0.05), "preto", bevel=0.008),
        k.caixa("faixa", (0.093, 0.04, 0.113), (0, -0.18, 0.05), "amarelo_sol", bevel=0.005),
    ] + _guarda(-0.02, -0.005, r=0.03) + _riscas(0.03, -0.03, 3, 0.058, "cinza_tecido")
    _base(p, "zumbido_01")


def faisca_01():
    """Pistola: ferrolho laranja com serrilhas, cano curto com bucha, punho
    ergonômico com cabo emborrachado, cão saliente atrás."""
    p = [
        k.caixa("ferrolho", (0.05, 0.20, 0.06), (0, -0.07, 0.07), "laranja", bevel=0.016),
    ] + [k.caixa("serrilha", (0.052, 0.008, 0.04), (0, 0.0 - i * 0.016, 0.075), "coral") for i in range(4)] + [
        k.caixa("armacao", (0.046, 0.16, 0.03), (0, -0.06, 0.03), "preto", bevel=0.008),
        k.cilindro("cano", 0.015, 0.05, (0, -0.19, 0.075), "metal_escuro", lados=10, rot=(90, 0, 0)),
        k.cilindro("bucha", 0.02, 0.015, (0, -0.172, 0.075), "metal_claro", lados=10, rot=(90, 0, 0)),
        k.caixa("punho", (0.045, 0.065, 0.13), (0, 0.0, -0.02), "preto", bevel=0.012, rot=(-12, 0, 0)),
        k.caixa("cabo_e", (0.048, 0.05, 0.09), (0, 0.003, -0.03), "laranja", bevel=0.01, rot=(-12, 0, 0)),
        k.caixa("cao", (0.016, 0.025, 0.025), (0, 0.04, 0.095), "metal_escuro", rot=(25, 0, 0)),
    ] + _guarda(-0.045, 0.0, r=0.025) + _miras(0.02, -0.15, 0.1, alta=0.015)
    _base(p, "faisca_01")


def gaviao_01():
    """Fuzil de precisão: cano longo com freio, luneta gorda com capas e
    torres de ajuste, bipé dobrado, coronha com apoio de rosto."""
    p = [
        k.caixa("corpo", (0.08, 0.40, 0.11), (0, -0.10, 0.05), "verde_militar", bevel=0.02),
        k.cilindro("cano", 0.019, 0.55, (0, -0.57, 0.07), "metal_escuro", lados=10, rot=(90, 0, 0)),
        k.cilindro("luneta", 0.034, 0.26, (0, -0.12, 0.17), "preto", lados=12, rot=(90, 0, 0)),
        k.cilindro("objetiva", 0.045, 0.06, (0, -0.27, 0.17), "preto", lados=12, rot=(90, 0, 0)),
        k.cilindro("lente", 0.039, 0.01, (0, -0.302, 0.17), "lente", lados=12, rot=(90, 0, 0)),
        k.cilindro("ocular", 0.04, 0.05, (0, 0.02, 0.17), "preto", lados=12, rot=(90, 0, 0)),
        k.cilindro("torre", 0.016, 0.03, (0, -0.12, 0.215), "amarelo_sol", lados=8),
        k.cilindro("torre_lado", 0.014, 0.03, (0.045, -0.12, 0.17), "amarelo_sol", lados=8, rot=(0, 90, 0)),
        k.caixa("suporte1", (0.03, 0.03, 0.05), (0, -0.05, 0.125), "metal_escuro"),
        k.caixa("suporte2", (0.03, 0.03, 0.05), (0, -0.19, 0.125), "metal_escuro"),
        k.caixa("punho", (0.055, 0.065, 0.12), (0, 0.02, -0.05), "preto", bevel=0.012, rot=(-15, 0, 0)),
        k.caixa("carregador", (0.05, 0.07, 0.09), (0, -0.14, -0.03), "metal_escuro", bevel=0.012),
        k.caixa("coronha", (0.07, 0.26, 0.12), (0, 0.19, 0.03), "verde_militar", bevel=0.025),
        k.caixa("apoio_rosto", (0.072, 0.14, 0.03), (0, 0.18, 0.1), "couro", bevel=0.012),
        k.caixa("soleira", (0.074, 0.03, 0.13), (0, 0.33, 0.03), "preto", bevel=0.012),
        k.caixa("bipe_e", (0.01, 0.2, 0.01), (-0.02, -0.42, 0.03), "metal_escuro"),
        k.caixa("bipe_d", (0.01, 0.2, 0.01), (0.02, -0.42, 0.03), "metal_escuro"),
        k.caixa("faixa", (0.083, 0.04, 0.113), (0, -0.28, 0.05), "amarelo_sol", bevel=0.005),
    ] + _guarda(-0.02, -0.005) + _quebra_chama(-0.86, 0.07, 0.019)
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
