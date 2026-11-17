"""Gera as skins originais do Ventania (Etapa 13 adiantada): personagens com
modelo, silhueta, materiais e acessórios próprios. Não são recolors do Recruta.

Todas usam o ESQUELETO PADRÃO e as MESMAS ANIMAÇÕES (gerar_personagem.py:
esqueleto() e animar()), com skinning rígido (cada peça segue um osso). Assim
as animações de locomoção, armas, queda, planador e aterrissagem servem a todas,
e a hitbox é a mesma de qualquer traje (ARCHITECTURE §8).

Coordenadas Blender: Z para cima, frente = -Y, esquerda = +X.
Ossos (alturas): quadril 0,95 · tronco 1,05–1,40 · cabeça 1,50–1,88 · ombros
x=±0,20 · cotovelo x=±0,47 · mão x=±0,72..0,86 (braços em T, z=1,38) ·
pernas x=±0,11, joelho 0,53, tornozelo 0,12.

Uso: python tools/assets/kit/blender/gerar_skins.py [id ...]
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy  # noqa: E402

import gerar_personagem as gp  # noqa: E402
import kit_comum as k  # noqa: E402

LADOS = (("Left", 1), ("Right", -1))


class Corpo:
    """Coleta as peças, cada uma presa (peso 1) a um osso."""

    def __init__(self):
        self.p = []

    def add(self, o, osso):
        self.p.append(gp._osso(o, osso))
        return o

    def lados(self, fn):
        for lado, s in LADOS:
            fn(lado, s)


def _montar(asset_id, construir):
    c = Corpo()
    construir(c)
    malha = k.unir(c.p, asset_id)
    arm = gp.esqueleto()
    malha.parent = arm
    mod = malha.modifiers.new("esqueleto", "ARMATURE")
    mod.object = arm
    malha["traje"] = asset_id
    gp.animar(arm)
    bpy.context.scene.frame_start, bpy.context.scene.frame_end = 1, 61


def _rebites(c, osso, pontos, cor="dourado", r=0.014):
    for i, p in enumerate(pontos):
        c.add(k.esfera(f"rebite{i}", r, p, cor, segmentos=6, aneis=4), osso)


# =============================================================== CAPITÃO MARÉ
def capitao_mare(c):
    """O Aquarista: um aquário de verdade no lugar da cabeça (vidro, moldura,
    água, cascalho, algas, pedra, castelinho, tampa com bomba de ar) sobre um
    corpo de robô de metal: placas rebitadas, sanfona na cintura, articulações
    esféricas, garras e botas de escafandro. Os peixes nadam pela Godot (TrajeFx)."""
    vidro = k.material_especial("M_vidro_ventania", (0.8, 0.95, 1.0, 0.2))
    agua = k.material_especial("M_agua_ventania", (0.2, 0.6, 0.95, 0.5))
    ME, MC, LT = "metal_escuro", "metal_claro", "dourado"
    # --- tronco mecânico
    c.add(k.caixa("pelve", (0.36, 0.24, 0.2), (0, 0, 0.94), ME, bevel=0.05), "Hips")
    for i, z in enumerate((1.02, 1.07, 1.12)):          # sanfona (cintura articulada)
        c.add(k.toro(f"sanfona{i}", 0.15 - i * 0.005, 0.03, (0, 0, z), ME, seg=12, seg_menor=4), "Spine")
    c.add(k.cilindro("eixo_cintura", 0.12, 0.16, (0, 0, 1.08), MC, lados=10), "Spine")
    c.add(k.caixa("peito", (0.48, 0.3, 0.32), (0, 0, 1.28), MC, bevel=0.07), "Chest")
    c.add(k.caixa("placa_peito", (0.32, 0.03, 0.2), (0, -0.155, 1.27), ME, bevel=0.012), "Chest")
    c.add(k.cilindro("manometro", 0.062, 0.03, (0.06, -0.175, 1.3), "branco", lados=12, rot=(90, 0, 0)), "Chest")
    c.add(k.toro("aro_manometro", 0.064, 0.012, (0.06, -0.19, 1.3), LT, rot=(90, 0, 0), seg=12, seg_menor=4), "Chest")
    c.add(k.caixa("ponteiro", (0.008, 0.01, 0.05), (0.07, -0.195, 1.31), "vermelho", rot=(0, 35, 0)), "Chest")
    c.add(k.caixa("grade", (0.1, 0.02, 0.05), (-0.08, -0.17, 1.24), "preto", bevel=0.005), "Chest")
    _rebites(c, "Chest", [(x, -0.172, z) for x in (-0.15, 0.15) for z in (1.19, 1.35)])
    _rebites(c, "Hips", [(x, -0.125, 0.94) for x in (-0.13, 0, 0.13)], cor=MC)
    # --- tanque de água nas costas, com mangueira até o aquário
    c.add(k.cilindro("tanque", 0.11, 0.38, (0, 0.24, 1.24), MC, lados=12), "Chest")
    c.add(k.esfera("tampa_tanque", 0.11, (0, 0.24, 1.43), LT, escala=(1, 1, 0.45), segmentos=10, aneis=5), "Chest")
    c.add(k.toro("cinta_tanque", 0.113, 0.015, (0, 0.24, 1.18), ME, seg=12, seg_menor=4), "Chest")
    c.add(k.cilindro("mangueira1", 0.022, 0.24, (0, 0.24, 1.55), "teal", lados=6), "Chest")
    c.add(k.cilindro("mangueira2", 0.022, 0.14, (0, 0.19, 1.67), "teal", lados=6, rot=(45, 0, 0)), "Head")
    # --- pescoço: colar e base do aquário
    c.add(k.toro("colar", 0.12, 0.035, (0, 0, 1.46), ME, seg=12, seg_menor=5), "Neck")
    c.add(k.cilindro("suporte", 0.07, 0.08, (0, 0, 1.5), MC, lados=8), "Neck")
    # --- AQUÁRIO (osso Head): tanque retangular de verdade
    L, P, Hh, zb = 0.46, 0.34, 0.36, 1.53                     # largura, profundidade, altura, base
    zc = zb + Hh / 2
    c.add(k.caixa("base_aquario", (L + 0.04, P + 0.04, 0.04), (0, 0, zb - 0.01), ME, bevel=0.01), "Head")
    c.add(k.usar_material(k.caixa("vidro", (L, P, Hh), (0, 0, zc), "branco"), vidro), "Head")
    c.add(k.usar_material(k.caixa("agua", (L - 0.03, P - 0.03, Hh * 0.74), (0, 0, zb + Hh * 0.37 + 0.005), "branco"), agua), "Head")
    for x in (-L / 2, L / 2):                                   # moldura: arestas verticais
        for y in (-P / 2, P / 2):
            c.add(k.caixa("aresta", (0.024, 0.024, Hh), (x, y, zc), ME), "Head")
    for y in (-P / 2, P / 2):                                   # moldura: em cima (frente/trás)
        c.add(k.caixa("borda_x", (L + 0.024, 0.024, 0.024), (0, y, zb + Hh), ME), "Head")
    for x in (-L / 2, L / 2):
        c.add(k.caixa("borda_y", (0.024, P + 0.024, 0.024), (x, 0, zb + Hh), ME), "Head")
    c.add(k.caixa("tampa", (L * 0.55, P * 0.6, 0.03), (0.06, 0.03, zb + Hh + 0.02), ME, bevel=0.008), "Head")
    c.add(k.cilindro("bomba_ar", 0.03, 0.07, (-0.13, 0.08, zb + Hh + 0.035), LT, lados=8), "Head")
    c.add(k.cilindro("tubo_ar", 0.008, Hh * 0.8, (-0.13, 0.08, zb + Hh * 0.55), "branco", lados=6), "Head")
    # dentro: cascalho colorido, pedra, algas e um castelinho
    import random
    rnd = random.Random(7)
    for i in range(16):
        x = rnd.uniform(-L / 2 + 0.04, L / 2 - 0.04)
        y = rnd.uniform(-P / 2 + 0.04, P / 2 - 0.04)
        cor = rnd.choice(["areia", "coral", "amarelo_sol", "areia", "branco"])
        c.add(k.esfera("cascalho", 0.024, (x, y, zb + 0.022), cor, escala=(1, 1, 0.6), segmentos=6, aneis=3), "Head")
    c.add(k.esfera("pedra", 0.055, (0.12, 0.06, zb + 0.05), "pedra_media", escala=(1.2, 1, 0.8), segmentos=8, aneis=5), "Head")
    for i, (x, y, h, inc) in enumerate(((-0.16, 0.08, 0.2, 8), (-0.12, 0.1, 0.15, -10), (0.15, -0.08, 0.17, 6))):
        c.add(k.cilindro("alga", 0.016, h, (x, y, zb + h / 2 + 0.02), "folha_media", lados=6, rot=(inc, 0, 0), raio_topo=0.004), "Head")
        c.add(k.cilindro("alga2", 0.012, h * 0.7, (x + 0.02, y, zb + h * 0.35 + 0.02), "folha_clara", lados=6, rot=(0, -inc, 0), raio_topo=0.003), "Head")
    c.add(k.caixa("castelo", (0.07, 0.06, 0.08), (0.03, 0.1, zb + 0.06), "pedra_clara", bevel=0.005), "Head")
    for dx in (-0.025, 0.025):
        c.add(k.caixa("ameia", (0.018, 0.06, 0.02), (0.03 + dx, 0.1, zb + 0.11), "pedra_clara"), "Head")
    c.add(k.caixa("porta_castelo", (0.024, 0.01, 0.035), (0.03, 0.068, zb + 0.04), "preto"), "Head")

    # --- braços: pistões, articulações esféricas e garras
    def braco(lado, s):
        c.add(k.esfera("ombro", 0.1, (s * 0.25, 0, 1.38), ME, segmentos=10, aneis=6), f"{lado}UpperArm")
        c.add(k.caixa("ombreira", (0.16, 0.2, 0.06), (s * 0.27, 0, 1.47), MC, bevel=0.02, rot=(0, s * -15, 0)), f"{lado}UpperArm")
        c.add(k.cilindro("braco", 0.05, 0.22, (s * 0.36, 0, 1.38), MC, lados=8, rot=(0, 90, 0)), f"{lado}UpperArm")
        c.add(k.cilindro("pistao_b", 0.016, 0.2, (s * 0.36, 0.06, 1.38), ME, lados=6, rot=(0, 90, 0)), f"{lado}UpperArm")
        c.add(k.esfera("cotovelo", 0.065, (s * 0.47, 0, 1.38), ME, segmentos=8, aneis=6), f"{lado}LowerArm")
        c.add(k.cilindro("antebraco", 0.058, 0.2, (s * 0.58, 0, 1.38), MC, lados=8, rot=(0, 90, 0), raio_topo=0.065), f"{lado}LowerArm")
        c.add(k.toro("faixa_ab", 0.064, 0.012, (s * 0.64, 0, 1.38), LT, rot=(0, 90, 0), seg=10, seg_menor=4), f"{lado}LowerArm")
        c.add(k.caixa("palma", (0.08, 0.1, 0.09), (s * 0.75, 0, 1.38), ME, bevel=0.015), f"{lado}Hand")
        c.add(k.caixa("garra_f", (0.08, 0.025, 0.035), (s * 0.82, -0.045, 1.36), MC, bevel=0.008, rot=(0, 0, s * 10)), f"{lado}Hand")
        c.add(k.caixa("garra_t", (0.08, 0.025, 0.035), (s * 0.82, 0.045, 1.36), MC, bevel=0.008, rot=(0, 0, s * -10)), f"{lado}Hand")

    # --- pernas: coxas de placa, joelhos esféricos, botas pesadas de escafandro
    def perna(lado, s):
        x = s * 0.11
        c.add(k.esfera("quadril_j", 0.075, (x, 0, 0.9), ME, segmentos=8, aneis=6), f"{lado}UpperLeg")
        c.add(k.cilindro("coxa", 0.072, 0.34, (x, 0, 0.72), MC, lados=8), f"{lado}UpperLeg")
        c.add(k.caixa("placa_coxa", (0.1, 0.03, 0.18), (x, -0.075, 0.74), ME, bevel=0.01), f"{lado}UpperLeg")
        c.add(k.esfera("joelho", 0.08, (x, 0, 0.53), ME, segmentos=8, aneis=6), f"{lado}LowerLeg")
        c.add(k.cilindro("canela", 0.068, 0.28, (x, 0, 0.37), MC, lados=8), f"{lado}LowerLeg")
        c.add(k.cilindro("pistao_p", 0.016, 0.26, (x, 0.07, 0.37), ME, lados=6), f"{lado}LowerLeg")
        c.add(k.cilindro("cano_bota", 0.1, 0.12, (x, 0, 0.18), ME, lados=10), f"{lado}LowerLeg")
        c.add(k.caixa("bota", (0.19, 0.32, 0.13), (x, -0.05, 0.065), ME, bevel=0.045), f"{lado}Foot")
        c.add(k.caixa("bico_bota", (0.17, 0.08, 0.1), (x, -0.19, 0.07), LT, bevel=0.03), f"{lado}Foot")
        c.add(k.caixa("sola", (0.2, 0.33, 0.03), (x, -0.05, 0.015), "preto"), f"{lado}Foot")

    c.lados(braco)
    c.lados(perna)


# =============================================================== ENTREGADOR
def entregador(c):
    """Entregador: capacete de moto fechado com viseira escura, jaqueta acolchoada
    vermelha com faixas refletivas, mochila térmica enorme (silhueta quadrada),
    suporte de celular no braço, calça cargo e tênis gigantes."""
    J, F, CAL = "vermelho", "amarelo_sol", "cinza_tecido"
    c.add(k.caixa("pelve", (0.38, 0.25, 0.22), (0, 0, 0.95), CAL, bevel=0.05), "Hips")
    c.add(k.caixa("pochete", (0.2, 0.06, 0.1), (0.06, -0.15, 0.98), "preto", bevel=0.02), "Hips")
    c.add(k.caixa("barriga", (0.4, 0.26, 0.18), (0, 0, 1.13), J, bevel=0.06), "Spine")
    c.add(k.caixa("peito", (0.5, 0.31, 0.32), (0, 0, 1.3), J, bevel=0.09), "Chest")
    for z in (1.18, 1.32):                                   # faixas refletivas
        c.add(k.caixa("refletiva", (0.51, 0.32, 0.03), (0, 0, z), F), "Chest")
    c.add(k.caixa("ziper", (0.02, 0.01, 0.3), (0, -0.16, 1.27), "metal_claro"), "Chest")
    c.add(k.toro("gola", 0.12, 0.05, (0, 0, 1.44), "preto", seg=12, seg_menor=5), "Chest")
    # mochila térmica (logo de vento original)
    c.add(k.caixa("mochila", (0.46, 0.34, 0.46), (0, 0.32, 1.27), "laranja", bevel=0.05), "Chest")
    c.add(k.caixa("tampa_mochila", (0.47, 0.35, 0.04), (0, 0.32, 1.51), F, bevel=0.015), "Chest")
    c.add(k.cilindro("logo", 0.1, 0.01, (0, 0.495, 1.27), "branco", lados=14, rot=(90, 0, 0)), "Chest")
    c.add(k.toro("logo_vento", 0.06, 0.014, (0.01, 0.502, 1.28), "laranja", rot=(90, 0, 0), seg=12, seg_menor=4), "Chest")
    c.add(k.caixa("logo_seta", (0.09, 0.01, 0.02), (0.04, 0.503, 1.24), "laranja", rot=(0, -20, 0)), "Chest")
    for s in (1, -1):
        c.add(k.caixa("alca", (0.05, 0.03, 0.34), (s * 0.13, -0.16, 1.3), "preto"), "Chest")
    # cabeça: capacete fechado
    c.add(k.cilindro("pescoco", 0.06, 0.1, (0, 0, 1.47), "pele_3", lados=8), "Neck")
    c.add(k.esfera("capacete", 0.245, (0, 0.01, 1.7), J, escala=(1.0, 1.05, 1.02), segmentos=14, aneis=10), "Head")
    c.add(k.esfera("viseira", 0.19, (0, -0.16, 1.71), "preto", escala=(1.0, 0.62, 0.6), segmentos=14, aneis=8), "Head")
    c.add(k.caixa("reflexo_viseira", (0.1, 0.01, 0.025), (-0.06, -0.278, 1.77), "azul_ceu", rot=(0, -15, 0)), "Head")
    c.add(k.caixa("queixeira", (0.26, 0.12, 0.09), (0, -0.14, 1.55), J, bevel=0.035), "Head")
    c.add(k.caixa("listra_cap", (0.05, 0.42, 0.04), (0, 0.02, 1.93), F, bevel=0.01), "Head")
    for s in (1, -1):
        c.add(k.cilindro("tranca", 0.03, 0.02, (s * 0.24, -0.06, 1.68), "metal_escuro", lados=8, rot=(0, 90, 0)), "Head")

    def braco(lado, s):
        c.add(k.esfera("ombro", 0.1, (s * 0.25, 0, 1.38), J, segmentos=10, aneis=6), f"{lado}UpperArm")
        c.add(k.cilindro("braco", 0.078, 0.25, (s * 0.35, 0, 1.38), J, lados=8, rot=(0, 90, 0)), f"{lado}UpperArm")
        c.add(k.toro("faixa_braco", 0.08, 0.014, (s * 0.38, 0, 1.38), F, rot=(0, 90, 0), seg=10, seg_menor=4), f"{lado}UpperArm")
        c.add(k.esfera("cotovelo", 0.07, (s * 0.47, 0, 1.38), J, segmentos=8, aneis=6), f"{lado}LowerArm")
        c.add(k.cilindro("antebraco", 0.07, 0.22, (s * 0.58, 0, 1.38), J, lados=8, rot=(0, 90, 0)), f"{lado}LowerArm")
        c.add(k.esfera("luva", 0.078, (s * 0.78, 0, 1.38), "preto", escala=(1.1, 0.85, 0.95), segmentos=10, aneis=6), f"{lado}Hand")
        if s == 1:                                            # celular preso no antebraço esquerdo
            c.add(k.caixa("suporte_cel", (0.11, 0.02, 0.07), (0.6, -0.08, 1.4), "preto", bevel=0.008), "LeftLowerArm")
            c.add(k.caixa("tela_cel", (0.09, 0.008, 0.055), (0.6, -0.092, 1.4), "azul_ceu"), "LeftLowerArm")

    def perna(lado, s):
        x = s * 0.11
        c.add(k.cilindro("coxa", 0.1, 0.42, (x, 0, 0.74), CAL, lados=8), f"{lado}UpperLeg")
        c.add(k.caixa("bolso_cargo", (0.05, 0.12, 0.13), (x + s * 0.1, 0, 0.72), "cinza_tecido", bevel=0.015), f"{lado}UpperLeg")
        c.add(k.esfera("joelho", 0.09, (x, 0, 0.53), CAL, segmentos=8, aneis=6), f"{lado}LowerLeg")
        c.add(k.cilindro("canela", 0.088, 0.3, (x, 0, 0.36), CAL, lados=8), f"{lado}LowerLeg")
        c.add(k.cilindro("meia", 0.075, 0.08, (x, 0, 0.17), "branco", lados=8), f"{lado}LowerLeg")
        c.add(k.caixa("tenis", (0.2, 0.36, 0.14), (x, -0.06, 0.07), "branco", bevel=0.06), f"{lado}Foot")
        c.add(k.caixa("sola_tenis", (0.21, 0.37, 0.045), (x, -0.06, 0.022), "laranja", bevel=0.015), f"{lado}Foot")
        c.add(k.caixa("faixa_tenis", (0.205, 0.14, 0.04), (x, -0.02, 0.1), J, rot=(20, 0, 0)), f"{lado}Foot")

    c.lados(braco)
    c.lados(perna)


# =============================================================== ESCAFANDRO
def escafandro(c):
    """Escafandro: mergulhador antigo com capacete de latão gigante (três vigias,
    grades, parafusos), peitoral rebitado, pesos de chumbo, traje grosso de lona
    e botas de chumbo. A cabeça É o capacete."""
    LAT, LONA, CH = "dourado", "areia", "metal_escuro"
    c.add(k.caixa("pelve", (0.42, 0.28, 0.24), (0, 0, 0.95), LONA, bevel=0.07), "Hips")
    c.add(k.caixa("cinto_peso", (0.44, 0.3, 0.07), (0, 0, 1.03), "couro", bevel=0.02), "Hips")
    for x in (-0.12, 0.0, 0.12):
        c.add(k.caixa("peso", (0.08, 0.05, 0.07), (x, -0.16, 1.03), CH, bevel=0.012), "Hips")
    c.add(k.caixa("barriga", (0.44, 0.3, 0.2), (0, 0, 1.14), LONA, bevel=0.08), "Spine")
    c.add(k.caixa("peito", (0.52, 0.34, 0.3), (0, 0, 1.3), LONA, bevel=0.1), "Chest")
    # peitoral (corselete) de latão rebitado
    c.add(k.caixa("corselete", (0.58, 0.4, 0.14), (0, 0, 1.43), LAT, bevel=0.05), "Chest")
    _rebites(c, "Chest", [(math.cos(a) * 0.27, math.sin(a) * 0.18, 1.45) for a in [i * math.tau / 12 for i in range(12)]], cor=CH, r=0.016)
    c.add(k.caixa("peso_peito", (0.2, 0.05, 0.14), (0, -0.2, 1.28), CH, bevel=0.02), "Chest")
    c.add(k.caixa("peso_costas", (0.24, 0.05, 0.18), (0, 0.2, 1.28), CH, bevel=0.02), "Chest")
    # capacete de latão (osso Head)
    c.add(k.esfera("capacete", 0.27, (0, 0, 1.71), LAT, segmentos=14, aneis=10), "Head")
    c.add(k.cilindro("vigia", 0.105, 0.06, (0, -0.255, 1.71), "lente", lados=14, rot=(90, 0, 0)), "Head")
    c.add(k.toro("aro_vigia", 0.11, 0.025, (0, -0.28, 1.71), CH, rot=(90, 0, 0), seg=14, seg_menor=5), "Head")
    for z in (1.67, 1.71, 1.75):
        c.add(k.caixa("grade_v", (0.17, 0.012, 0.012), (0, -0.29, z), CH), "Head")
    for s in (1, -1):
        c.add(k.cilindro("vigia_lado", 0.07, 0.05, (s * 0.255, 0, 1.72), "lente", lados=12, rot=(0, 90, 0)), "Head")
        c.add(k.toro("aro_lado", 0.075, 0.02, (s * 0.275, 0, 1.72), CH, rot=(0, 90, 0), seg=12, seg_menor=4), "Head")
    c.add(k.cilindro("valvula", 0.05, 0.08, (0, 0.2, 1.88), CH, lados=8, rot=(-40, 0, 0)), "Head")
    c.add(k.toro("volante", 0.05, 0.012, (0, 0.23, 1.92), "vermelho", rot=(-40, 0, 0), seg=10, seg_menor=4), "Head")
    c.add(k.cilindro("mangueira", 0.03, 0.3, (0, 0.28, 1.6), "preto", lados=8, rot=(25, 0, 0)), "Head")
    _rebites(c, "Head", [(math.cos(a) * 0.255, math.sin(a) * 0.255, 1.5) for a in [i * math.tau / 10 for i in range(10)]], cor=CH, r=0.018)

    def braco(lado, s):
        c.add(k.esfera("ombro", 0.11, (s * 0.27, 0, 1.38), LONA, segmentos=10, aneis=6), f"{lado}UpperArm")
        c.add(k.cilindro("braco", 0.09, 0.24, (s * 0.37, 0, 1.38), LONA, lados=8, rot=(0, 90, 0)), f"{lado}UpperArm")
        c.add(k.esfera("cotovelo", 0.085, (s * 0.48, 0, 1.38), LONA, segmentos=8, aneis=6), f"{lado}LowerArm")
        c.add(k.cilindro("antebraco", 0.08, 0.2, (s * 0.58, 0, 1.38), LONA, lados=8, rot=(0, 90, 0)), f"{lado}LowerArm")
        c.add(k.toro("punho_metal", 0.078, 0.02, (s * 0.68, 0, 1.38), LAT, rot=(0, 90, 0), seg=10, seg_menor=4), f"{lado}LowerArm")
        c.add(k.esfera("luva", 0.085, (s * 0.78, 0, 1.38), "couro", escala=(1.1, 0.85, 0.95), segmentos=10, aneis=6), f"{lado}Hand")

    def perna(lado, s):
        x = s * 0.12
        c.add(k.cilindro("coxa", 0.11, 0.42, (x, 0, 0.74), LONA, lados=8), f"{lado}UpperLeg")
        c.add(k.esfera("joelho", 0.1, (x, 0, 0.53), LONA, segmentos=8, aneis=6), f"{lado}LowerLeg")
        c.add(k.cilindro("canela", 0.1, 0.28, (x, 0, 0.36), LONA, lados=8), f"{lado}LowerLeg")
        c.add(k.cilindro("cano_bota", 0.115, 0.14, (x, 0, 0.17), CH, lados=10), f"{lado}LowerLeg")
        c.add(k.caixa("bota", (0.21, 0.34, 0.14), (x, -0.05, 0.07), CH, bevel=0.04), f"{lado}Foot")
        c.add(k.caixa("bico_latao", (0.19, 0.09, 0.11), (x, -0.2, 0.075), LAT, bevel=0.03), f"{lado}Foot")
        c.add(k.caixa("sola", (0.22, 0.35, 0.035), (x, -0.05, 0.017), "preto"), f"{lado}Foot")

    c.lados(braco)
    c.lados(perna)


# =============================================================== FAZ-TUDO
def faz_tudo(c):
    """Faz-Tudo, o técnico de manutenção: robô amarelo de serviço com cabeça de
    monitor (rosto na tela), antena com giroflex, faixas de alerta, painel de
    botões, mão direita de chave inglesa, mão esquerda de garra e pés de esteira."""
    AM, ME, MC = "amarelo_sol", "metal_escuro", "metal_claro"
    c.add(k.caixa("pelve", (0.34, 0.24, 0.18), (0, 0, 0.95), ME, bevel=0.04), "Hips")
    c.add(k.caixa("cinto_ferramentas", (0.4, 0.28, 0.06), (0, 0, 1.0), "couro", bevel=0.015), "Hips")
    c.add(k.cilindro("chave_fenda", 0.012, 0.16, (0.16, -0.14, 0.97), "vermelho", lados=6, rot=(0, 15, 0)), "Hips")
    c.add(k.cilindro("lanterna", 0.025, 0.1, (-0.17, -0.12, 0.98), "preto", lados=8), "Hips")
    c.add(k.cilindro("cintura", 0.11, 0.16, (0, 0, 1.08), MC, lados=10), "Spine")
    c.add(k.caixa("corpo", (0.5, 0.36, 0.38), (0, 0, 1.28), AM, bevel=0.08), "Chest")
    c.add(k.caixa("painel", (0.26, 0.02, 0.16), (0, -0.185, 1.28), "preto", bevel=0.01), "Chest")
    for i, cor in enumerate(("vermelho", "folha_clara", "azul_ceu")):
        c.add(k.esfera("botao", 0.022, (-0.07 + i * 0.07, -0.2, 1.32), cor, segmentos=6, aneis=4), "Chest")
    c.add(k.caixa("barra_nivel", (0.18, 0.012, 0.025), (0, -0.2, 1.24), "folha_clara"), "Chest")
    for i in range(4):                                          # faixas de alerta (diagonais)
        c.add(k.caixa("alerta", (0.04, 0.37, 0.09), (-0.18 + i * 0.12, 0, 1.12), "preto", rot=(0, 35, 0)), "Chest")
    c.add(k.caixa("bateria", (0.3, 0.12, 0.3), (0, 0.24, 1.28), ME, bevel=0.03), "Chest")
    c.add(k.caixa("carga", (0.04, 0.02, 0.18), (0.08, 0.305, 1.28), "folha_clara"), "Chest")
    # cabeça: monitor com rosto, antena com giroflex
    c.add(k.cilindro("pescoco", 0.05, 0.12, (0, 0, 1.47), ME, lados=8), "Neck")
    c.add(k.caixa("monitor", (0.42, 0.3, 0.32), (0, 0, 1.69), AM, bevel=0.05), "Head")
    c.add(k.caixa("tela", (0.34, 0.02, 0.22), (0, -0.155, 1.69), "preto", bevel=0.02), "Head")
    for s in (1, -1):
        c.add(k.caixa("olho", (0.06, 0.012, 0.07), (s * 0.075, -0.168, 1.71), "azul_ceu", bevel=0.01), "Head")
        c.add(k.cilindro("orelha", 0.05, 0.05, (s * 0.225, 0, 1.69), ME, lados=10, rot=(0, 90, 0)), "Head")
    c.add(k.caixa("boca", (0.1, 0.012, 0.018), (0, -0.168, 1.62), "azul_ceu"), "Head")
    c.add(k.cilindro("antena", 0.012, 0.2, (0.12, 0.05, 1.94), ME, lados=6), "Head")
    c.add(k.esfera("giroflex", 0.045, (0.12, 0.05, 2.05), "laranja", escala=(1, 1, 1.2), segmentos=8, aneis=6), "Head")

    def braco(lado, s):
        c.add(k.esfera("ombro", 0.085, (s * 0.26, 0, 1.38), ME, segmentos=8, aneis=6), f"{lado}UpperArm")
        c.add(k.cilindro("braco", 0.04, 0.22, (s * 0.36, 0, 1.38), MC, lados=8, rot=(0, 90, 0)), f"{lado}UpperArm")
        c.add(k.esfera("cotovelo", 0.06, (s * 0.47, 0, 1.38), ME, segmentos=8, aneis=6), f"{lado}LowerArm")
        c.add(k.cilindro("antebraco", 0.05, 0.2, (s * 0.58, 0, 1.38), AM, lados=8, rot=(0, 90, 0), raio_topo=0.06), f"{lado}LowerArm")
        if s == -1:                                             # mão direita: chave inglesa
            c.add(k.caixa("cabo_chave", (0.14, 0.04, 0.03), (-0.76, 0, 1.38), MC, bevel=0.008), "RightHand")
            c.add(k.toro("boca_chave", 0.045, 0.018, (-0.85, 0, 1.38), MC, rot=(90, 0, 0), seg=10, seg_menor=4), "RightHand")
        else:                                                   # mão esquerda: garra
            c.add(k.caixa("pulso", (0.06, 0.09, 0.08), (0.74, 0, 1.38), ME, bevel=0.015), "LeftHand")
            for dy in (-0.035, 0.035):
                c.add(k.caixa("dedo", (0.09, 0.022, 0.03), (0.81, dy, 1.38), AM, bevel=0.008, rot=(0, 0, 12 if dy > 0 else -12)), "LeftHand")

    def perna(lado, s):
        x = s * 0.12
        c.add(k.cilindro("coxa", 0.06, 0.4, (x, 0, 0.74), MC, lados=8), f"{lado}UpperLeg")
        c.add(k.cilindro("pistao", 0.02, 0.36, (x, -0.06, 0.72), ME, lados=6), f"{lado}UpperLeg")
        c.add(k.esfera("joelho", 0.075, (x, 0, 0.53), AM, segmentos=8, aneis=6), f"{lado}LowerLeg")
        c.add(k.cilindro("canela", 0.07, 0.26, (x, 0, 0.37), AM, lados=8), f"{lado}LowerLeg")
        c.add(k.caixa("esteira", (0.16, 0.36, 0.13), (x, -0.04, 0.07), ME, bevel=0.06), f"{lado}Foot")
        for dy in (-0.15, -0.04, 0.07):
            c.add(k.cilindro("roda", 0.04, 0.17, (x, dy, 0.065), MC, lados=8, rot=(0, 90, 0)), f"{lado}Foot")

    c.lados(braco)
    c.lados(perna)


# =============================================================== ESPANTALHO
def espantalho(c):
    """Espantalho: cabeça de saco de estopa costurada (olhos em X, boca em zigue-
    zague), chapéu de palha de aba larga, camisa xadrez remendada, macacão,
    tufos de palha saindo das mangas, gola e barras, e um corvo no ombro."""
    PAL, CAM, MAC = "madeira_clara", "vermelho", "jeans"

    def tufo(nome, pos, rot, osso, n=3, comp=0.09):
        for i in range(n):
            c.add(k.cilindro(nome, 0.018, comp, pos, PAL if i % 2 == 0 else "amarelo_sol", lados=4,
                             rot=(rot[0] + (i - 1) * 18, rot[1] + (i - 1) * 14, rot[2]), raio_topo=0.002), osso)

    c.add(k.caixa("pelve", (0.38, 0.25, 0.22), (0, 0, 0.95), MAC, bevel=0.05), "Hips")
    c.add(k.caixa("barriga", (0.36, 0.22, 0.17), (0, 0, 1.13), CAM, bevel=0.04), "Spine")
    c.add(k.caixa("peito", (0.44, 0.27, 0.3), (0, 0, 1.3), CAM, bevel=0.05), "Chest")
    for x in (-0.12, 0.0, 0.12):                                # xadrez
        c.add(k.caixa("xadrez_v", (0.025, 0.28, 0.31), (x, 0, 1.3), "preto"), "Chest")
    c.add(k.caixa("xadrez_h", (0.45, 0.28, 0.025), (0, 0, 1.3), "preto"), "Chest")
    c.add(k.caixa("remendo", (0.1, 0.02, 0.1), (0.1, -0.14, 1.22), "folha_media", rot=(0, 8, 0)), "Chest")
    c.add(k.caixa("remendo2", (0.08, 0.02, 0.08), (-0.12, -0.14, 1.36), "azul_ceu", rot=(0, -12, 0)), "Chest")
    for s in (1, -1):                                          # alças do macacão
        c.add(k.caixa("alca", (0.06, 0.29, 0.34), (s * 0.12, 0, 1.24), MAC), "Chest")
        c.add(k.esfera("botao", 0.02, (s * 0.12, -0.15, 1.36), "dourado", segmentos=6, aneis=4), "Chest")
    c.add(k.caixa("peitilho", (0.3, 0.02, 0.16), (0, -0.14, 1.17), MAC), "Chest")
    tufo("palha_gola", (0, -0.08, 1.46), (-30, 0, 0), "Chest", n=4)
    # cabeça de estopa
    c.add(k.cilindro("pescoco", 0.05, 0.1, (0, 0, 1.47), PAL, lados=6), "Neck")
    c.add(k.esfera("saco", 0.21, (0, 0, 1.68), "areia", escala=(0.95, 0.9, 1.08), segmentos=12, aneis=8), "Head")
    c.add(k.toro("corda", 0.11, 0.02, (0, 0, 1.52), "madeira_media", seg=10, seg_menor=4), "Head")
    for s in (1, -1):                                          # olhos costurados em X
        for r in (45, -45):
            c.add(k.caixa("ponto_olho", (0.07, 0.012, 0.015), (s * 0.07, -0.19, 1.72), "preto", rot=(0, r, 0)), "Head")
    for i in range(5):                                         # boca em zigue-zague
        c.add(k.caixa("ponto_boca", (0.04, 0.012, 0.012), (-0.08 + i * 0.04, -0.195, 1.6 + (0.012 if i % 2 else -0.012)), "preto",
                      rot=(0, 30 if i % 2 else -30, 0)), "Head")
    # chapéu de palha
    c.add(k.cilindro("aba", 0.36, 0.025, (0, 0.02, 1.84), PAL, lados=16, rot=(-6, 4, 0)), "Head")
    c.add(k.cilindro("copa", 0.15, 0.17, (0, 0.03, 1.94), PAL, lados=12, raio_topo=0.12), "Head")
    c.add(k.cilindro("fita", 0.152, 0.035, (0, 0.03, 1.875), "vermelho", lados=12), "Head")
    tufo("palha_chapeu", (0.14, 0.05, 1.8), (0, 60, 0), "Head", n=3, comp=0.08)
    # corvo no ombro esquerdo
    c.add(k.esfera("corvo", 0.065, (0.26, 0.02, 1.5), "preto", escala=(0.8, 1.3, 0.9), segmentos=8, aneis=6), "LeftShoulder")
    c.add(k.esfera("corvo_cab", 0.04, (0.26, -0.07, 1.57), "preto", segmentos=8, aneis=6), "LeftShoulder")
    c.add(k.cilindro("bico", 0.014, 0.05, (0.26, -0.115, 1.57), "amarelo_sol", lados=5, rot=(90, 0, 0), raio_topo=0.002), "LeftShoulder")
    c.add(k.esfera("olho_corvo", 0.008, (0.285, -0.095, 1.585), "branco", segmentos=4, aneis=3), "LeftShoulder")
    c.add(k.caixa("rabo_corvo", (0.05, 0.08, 0.015), (0.26, 0.1, 1.48), "preto", rot=(20, 0, 0)), "LeftShoulder")

    def braco(lado, s):
        c.add(k.esfera("ombro", 0.08, (s * 0.24, 0, 1.38), CAM, segmentos=10, aneis=6), f"{lado}UpperArm")
        c.add(k.cilindro("braco", 0.065, 0.25, (s * 0.35, 0, 1.38), CAM, lados=8, rot=(0, 90, 0)), f"{lado}UpperArm")
        c.add(k.esfera("cotovelo", 0.06, (s * 0.47, 0, 1.38), CAM, segmentos=8, aneis=6), f"{lado}LowerArm")
        c.add(k.cilindro("antebraco", 0.065, 0.2, (s * 0.58, 0, 1.38), CAM, lados=8, rot=(0, 90, 0), raio_topo=0.075), f"{lado}LowerArm")
        tufo("palha_manga", (s * 0.7, 0, 1.38), (0, 90 * s, 0), f"{lado}LowerArm", n=3, comp=0.08)
        c.add(k.esfera("luva", 0.07, (s * 0.78, 0, 1.38), "couro", escala=(1.1, 0.8, 0.95), segmentos=8, aneis=6), f"{lado}Hand")

    def perna(lado, s):
        x = s * 0.11
        c.add(k.cilindro("coxa", 0.1, 0.42, (x, 0, 0.74), MAC, lados=8), f"{lado}UpperLeg")
        c.add(k.caixa("remendo_joelho", (0.09, 0.02, 0.09), (x, -0.1, 0.56), "amarelo_sol", rot=(0, 10, 0)), f"{lado}LowerLeg")
        c.add(k.esfera("joelho", 0.09, (x, 0, 0.53), MAC, segmentos=8, aneis=6), f"{lado}LowerLeg")
        c.add(k.cilindro("canela", 0.09, 0.3, (x, 0, 0.37), MAC, lados=8, raio_topo=0.095), f"{lado}LowerLeg")
        tufo("palha_barra", (x, 0, 0.2), (180, 0, 0), f"{lado}LowerLeg", n=3, comp=0.07)
        c.add(k.caixa("bota", (0.17, 0.3, 0.12), (x, -0.05, 0.07), "couro", bevel=0.04), f"{lado}Foot")
        c.add(k.caixa("sola", (0.18, 0.31, 0.03), (x, -0.05, 0.015), "preto"), f"{lado}Foot")

    c.lados(braco)
    c.lados(perna)


# =============================================================== EXPLORADOR DAS NUVENS
def explorador(c):
    """Explorador das Nuvens: gorro de aviador de couro com abas, óculos grandes
    sobre os olhos, jaqueta de voo com gola de pelúcia, cachecol comprido ao
    vento, bússola no peito, tubo de mapas e uma mochila-hélice."""
    JQ, CR, PEL = "madeira_media", "couro", "branco"
    c.add(k.caixa("pelve", (0.38, 0.25, 0.22), (0, 0, 0.95), "terra", bevel=0.05), "Hips")
    c.add(k.caixa("cinto", (0.4, 0.27, 0.05), (0, 0, 1.04), CR), "Hips")
    c.add(k.caixa("barriga", (0.38, 0.25, 0.17), (0, 0, 1.13), JQ, bevel=0.05), "Spine")
    c.add(k.caixa("peito", (0.47, 0.3, 0.31), (0, 0, 1.3), JQ, bevel=0.07), "Chest")
    c.add(k.caixa("ziper", (0.02, 0.01, 0.3), (0.04, -0.155, 1.27), "metal_claro", rot=(0, 6, 0)), "Chest")
    c.add(k.toro("gola_pelucia", 0.13, 0.065, (0, 0, 1.44), PEL, seg=12, seg_menor=6), "Chest")
    c.add(k.cilindro("bussola", 0.05, 0.03, (-0.1, -0.165, 1.33), "dourado", lados=12, rot=(90, 0, 0)), "Chest")
    c.add(k.cilindro("mostrador", 0.04, 0.01, (-0.1, -0.182, 1.33), "branco", lados=12, rot=(90, 0, 0)), "Chest")
    c.add(k.caixa("agulha", (0.008, 0.008, 0.05), (-0.1, -0.188, 1.33), "vermelho", rot=(0, 30, 0)), "Chest")
    # cachecol ao vento (para trás)
    c.add(k.caixa("cachecol1", (0.1, 0.32, 0.05), (0.06, 0.28, 1.43), "azul_ceu", rot=(-12, 0, 6)), "Chest")
    c.add(k.caixa("cachecol2", (0.09, 0.22, 0.05), (0.09, 0.5, 1.39), "azul_ceu", rot=(-28, 0, 10)), "Chest")
    # mochila-hélice e tubo de mapas
    c.add(k.caixa("motor", (0.24, 0.16, 0.26), (0, 0.24, 1.27), "metal_escuro", bevel=0.04), "Chest")
    c.add(k.cilindro("eixo", 0.025, 0.12, (0, 0.36, 1.3), "metal_claro", lados=6, rot=(90, 0, 0)), "Chest")
    for a in (0, 90):
        c.add(k.caixa("pa_helice", (0.5, 0.012, 0.06), (0, 0.42, 1.3), "madeira_clara", bevel=0.01, rot=(0, a + 20, 0)), "Chest")
    c.add(k.esfera("cubo", 0.035, (0, 0.43, 1.3), "vermelho", segmentos=6, aneis=4), "Chest")
    c.add(k.cilindro("tubo_mapas", 0.045, 0.5, (-0.22, 0.2, 1.25), CR, lados=8, rot=(0, 25, 0)), "Chest")
    # cabeça
    c.add(k.cilindro("pescoco", 0.06, 0.1, (0, 0, 1.47), "pele_2", lados=8), "Neck")
    c.add(k.esfera("cabeca", 0.2, (0, 0, 1.67), "pele_2", escala=(1.0, 0.95, 1.05)), "Head")
    c.add(k.esfera("gorro", 0.215, (0, 0.02, 1.71), CR, escala=(1.04, 1.03, 0.9), segmentos=12, aneis=8), "Head")
    for s in (1, -1):
        c.add(k.caixa("aba_orelha", (0.04, 0.12, 0.16), (s * 0.2, 0.02, 1.6), CR, bevel=0.02, rot=(0, s * 8, 0)), "Head")
        c.add(k.esfera("pelucia_aba", 0.03, (s * 0.215, 0.02, 1.53), PEL, segmentos=6, aneis=4), "Head")
        c.add(k.cilindro("lente", 0.06, 0.045, (s * 0.08, -0.2, 1.68), "lente", lados=12, rot=(90, 0, 0)), "Head")
        c.add(k.toro("aro", 0.064, 0.016, (s * 0.08, -0.215, 1.68), "dourado", rot=(90, 0, 0), seg=12, seg_menor=4), "Head")
    c.add(k.caixa("ponte_oculos", (0.05, 0.02, 0.02), (0, -0.22, 1.69), "dourado"), "Head")
    c.add(k.toro("faixa_oculos", 0.205, 0.015, (0, 0, 1.68), "preto", seg=14, seg_menor=4), "Head")
    c.add(k.esfera("nariz", 0.03, (0, -0.205, 1.62), "pele_3", segmentos=8, aneis=6), "Head")
    c.add(k.caixa("sorriso", (0.07, 0.012, 0.015), (0, -0.19, 1.57), "preto", rot=(0, 0, 0)), "Head")

    def braco(lado, s):
        c.add(k.esfera("ombro", 0.09, (s * 0.24, 0, 1.38), JQ, segmentos=10, aneis=6), f"{lado}UpperArm")
        c.add(k.cilindro("braco", 0.07, 0.25, (s * 0.35, 0, 1.38), JQ, lados=8, rot=(0, 90, 0)), f"{lado}UpperArm")
        c.add(k.caixa("remendo_asa", (0.08, 0.02, 0.06), (s * 0.35, -0.07, 1.38), "amarelo_sol"), f"{lado}UpperArm")
        c.add(k.esfera("cotovelo", 0.065, (s * 0.47, 0, 1.38), JQ, segmentos=8, aneis=6), f"{lado}LowerArm")
        c.add(k.cilindro("antebraco", 0.065, 0.2, (s * 0.58, 0, 1.38), JQ, lados=8, rot=(0, 90, 0)), f"{lado}LowerArm")
        c.add(k.toro("punho_pelucia", 0.07, 0.03, (s * 0.69, 0, 1.38), PEL, rot=(0, 90, 0), seg=10, seg_menor=4), f"{lado}LowerArm")
        c.add(k.esfera("luva", 0.078, (s * 0.78, 0, 1.38), CR, escala=(1.1, 0.8, 0.95), segmentos=10, aneis=6), f"{lado}Hand")

    def perna(lado, s):
        x = s * 0.11
        c.add(k.cilindro("coxa", 0.098, 0.42, (x, 0, 0.74), "terra", lados=8), f"{lado}UpperLeg")
        c.add(k.esfera("joelheira", 0.09, (x, -0.02, 0.53), CR, segmentos=8, aneis=6), f"{lado}LowerLeg")
        c.add(k.cilindro("canela", 0.085, 0.24, (x, 0, 0.38), "terra", lados=8), f"{lado}LowerLeg")
        c.add(k.cilindro("bota_alta", 0.1, 0.24, (x, 0, 0.2), CR, lados=8), f"{lado}LowerLeg")
        c.add(k.caixa("bota", (0.17, 0.3, 0.12), (x, -0.05, 0.07), CR, bevel=0.04), f"{lado}Foot")
        c.add(k.caixa("sola", (0.18, 0.31, 0.03), (x, -0.05, 0.015), "preto"), f"{lado}Foot")

    c.lados(braco)
    c.lados(perna)


# =============================================================== BOTÂNICO
def botanico(c):
    """Botânico: uma criatura-planta. Tronco de casca de árvore com musgo, braços
    de galho com brotos, cabeça de madeira com coroa de folhas e uma flor de
    vento, ombreiras de cogumelo, vinhas enroladas, raízes nos pés e um regador."""
    CAS, MAD, FO, FC, FE = "tronco", "madeira_clara", "folha_media", "folha_clara", "folha_escura"
    c.add(k.caixa("pelve", (0.34, 0.24, 0.2), (0, 0, 0.95), CAS, bevel=0.06), "Hips")
    c.add(k.cilindro("tronco_baixo", 0.15, 0.18, (0, 0, 1.11), CAS, lados=8), "Spine")
    c.add(k.cilindro("tronco_alto", 0.21, 0.3, (0, 0, 1.3), CAS, lados=9, raio_topo=0.17), "Chest")
    for i, (x, z, r) in enumerate(((0.12, 1.22, 0.07), (-0.14, 1.35, 0.06), (0.05, 1.4, 0.05))):
        c.add(k.esfera("musgo", r, (x, -0.13, z), FE, escala=(1, 0.5, 0.8), segmentos=8, aneis=5), "Chest")
    c.add(k.esfera("no_madeira", 0.035, (-0.05, -0.19, 1.22), "madeira_escura", segmentos=6, aneis=4), "Chest")
    c.add(k.toro("vinha_tronco", 0.2, 0.018, (0, 0, 1.24), FO, rot=(0, 18, 0), seg=14, seg_menor=4), "Chest")
    for s in (1, -1):                                          # ombreiras de cogumelo
        c.add(k.esfera("chapeu_cog", 0.11, (s * 0.23, 0, 1.47), "coral", escala=(1, 1, 0.55), segmentos=10, aneis=6), "Chest")
        for dx, dy in ((0.04, -0.05), (-0.03, 0.04), (0.0, 0.0)):
            c.add(k.esfera("pinta", 0.018, (s * 0.23 + dx, dy, 1.52), "branco", segmentos=5, aneis=3), "Chest")
    # regador na cintura
    c.add(k.cilindro("regador", 0.06, 0.1, (0.2, -0.05, 0.95), "metal_claro", lados=8), "Hips")
    c.add(k.cilindro("bico_regador", 0.012, 0.12, (0.26, -0.1, 0.98), "metal_claro", lados=5, rot=(0, 60, 30)), "Hips")
    # cabeça de madeira com coroa de folhas e flor
    c.add(k.cilindro("pescoco", 0.06, 0.12, (0, 0, 1.47), CAS, lados=6), "Neck")
    c.add(k.esfera("cabeca", 0.19, (0, 0, 1.66), MAD, escala=(1, 0.95, 1.08), segmentos=12, aneis=8), "Head")
    for s in (1, -1):
        c.add(k.esfera("olho", 0.03, (s * 0.07, -0.17, 1.68), "preto", escala=(0.8, 0.5, 1.2), segmentos=8, aneis=5), "Head")
        c.add(k.esfera("bochecha", 0.025, (s * 0.11, -0.16, 1.62), "coral", escala=(1, 0.4, 0.8), segmentos=6, aneis=4), "Head")
    c.add(k.caixa("sorriso", (0.06, 0.012, 0.012), (0, -0.183, 1.6), "madeira_escura"), "Head")
    import random
    rnd = random.Random(3)
    for i in range(11):                                        # coroa de folhas
        a = i / 11 * math.tau
        c.add(k.esfera("folha", 0.065, (math.cos(a) * 0.15, math.sin(a) * 0.13 + 0.02, 1.8 + rnd.uniform(-0.02, 0.03)),
                       FC if i % 2 else FO, escala=(1.3, 0.6, 0.5), segmentos=6, aneis=4, rot=(0, 0, math.degrees(a))), "Head")
    # flor de vento (pétalas como um cata-vento)
    c.add(k.cilindro("caule", 0.012, 0.16, (0.05, 0.04, 1.9), FE, lados=5, rot=(0, 10, 0)), "Head")
    c.add(k.esfera("miolo", 0.035, (0.065, 0.04, 1.99), "amarelo_sol", segmentos=8, aneis=5), "Head")
    for i in range(5):
        a = i / 5 * 360
        c.add(k.caixa("petala", (0.06, 0.012, 0.025), (0.065 + math.cos(math.radians(a)) * 0.05, 0.04, 1.99 + math.sin(math.radians(a)) * 0.05),
                      "rosa", rot=(0, -a, 0), bevel=0.008), "Head")

    def braco(lado, s):
        c.add(k.esfera("ombro", 0.07, (s * 0.24, 0, 1.38), CAS, segmentos=8, aneis=6), f"{lado}UpperArm")
        c.add(k.cilindro("galho", 0.05, 0.25, (s * 0.35, 0, 1.38), CAS, lados=6, rot=(0, 90, 0), raio_topo=0.045), f"{lado}UpperArm")
        c.add(k.cilindro("broto", 0.012, 0.09, (s * 0.38, 0, 1.44), CAS, lados=4, rot=(0, s * 30, 0), raio_topo=0.002), f"{lado}UpperArm")
        c.add(k.esfera("folhinha", 0.025, (s * 0.4, 0, 1.49), FC, escala=(1.3, 0.5, 0.7), segmentos=6, aneis=3), f"{lado}UpperArm")
        c.add(k.toro("vinha_braco", 0.055, 0.012, (s * 0.33, 0, 1.38), FO, rot=(0, 70, 0), seg=10, seg_menor=3), f"{lado}UpperArm")
        c.add(k.esfera("cotovelo", 0.05, (s * 0.47, 0, 1.38), CAS, segmentos=8, aneis=5), f"{lado}LowerArm")
        c.add(k.cilindro("galho2", 0.044, 0.22, (s * 0.58, 0, 1.38), CAS, lados=6, rot=(0, 90, 0), raio_topo=0.04), f"{lado}LowerArm")
        c.add(k.esfera("mao", 0.06, (s * 0.76, 0, 1.38), MAD, segmentos=8, aneis=5), f"{lado}Hand")
        for dz in (-0.03, 0.0, 0.03):
            c.add(k.cilindro("dedo", 0.012, 0.07, (s * 0.83, -0.01, 1.38 + dz), MAD, lados=4, rot=(0, 90, 0), raio_topo=0.006), f"{lado}Hand")

    def perna(lado, s):
        x = s * 0.11
        c.add(k.cilindro("coxa", 0.085, 0.42, (x, 0, 0.74), CAS, lados=7), f"{lado}UpperLeg")
        c.add(k.toro("vinha_perna", 0.09, 0.014, (x, 0, 0.68), FO, rot=(20, 0, 0), seg=10, seg_menor=3), f"{lado}UpperLeg")
        c.add(k.esfera("joelho", 0.075, (x, 0, 0.53), CAS, segmentos=8, aneis=5), f"{lado}LowerLeg")
        c.add(k.cilindro("canela", 0.08, 0.32, (x, 0, 0.35), CAS, lados=7, raio_topo=0.07), f"{lado}LowerLeg")
        c.add(k.cilindro("base_raiz", 0.09, 0.08, (x, -0.02, 0.07), CAS, lados=7, raio_topo=0.07), f"{lado}Foot")
        for a in (-50, -15, 20, 140):                           # raízes espalhadas
            ra = math.radians(a)
            c.add(k.cilindro("raiz", 0.028, 0.16, (x + math.sin(ra) * 0.08, -0.02 - math.cos(ra) * 0.1, 0.035), CAS, lados=5,
                             rot=(80, 0, a), raio_topo=0.008), f"{lado}Foot")

    c.lados(braco)
    c.lados(perna)


# =============================================================== ASTRÔNOMO
def astronomo(c):
    """Astrônomo: a cabeça é um pequeno planeta com rosto, anel e uma lua; sobretudo
    estrelado com capa, cinto com luneta, telescópio de latão nas costas."""
    PL, CAPA, OUR = "azul_tormenta", "roxo", "dourado"
    c.add(k.caixa("pelve", (0.38, 0.26, 0.22), (0, 0, 0.95), "preto", bevel=0.05), "Hips")
    c.add(k.caixa("cinto", (0.4, 0.28, 0.05), (0, 0, 1.04), OUR), "Hips")
    c.add(k.cilindro("luneta_cinto", 0.025, 0.18, (-0.2, -0.05, 0.98), OUR, lados=6, rot=(0, 30, 0)), "Hips")
    c.add(k.caixa("barriga", (0.38, 0.25, 0.17), (0, 0, 1.13), CAPA, bevel=0.05), "Spine")
    c.add(k.caixa("peito", (0.46, 0.3, 0.31), (0, 0, 1.3), CAPA, bevel=0.07), "Chest")
    for i, (x, z) in enumerate(((0.12, 1.36), (-0.1, 1.2), (0.05, 1.15), (-0.15, 1.38), (0.17, 1.2))):
        c.add(k.esfera("estrela", 0.018, (x, -0.155, z), "amarelo_sol", segmentos=4, aneis=3), "Chest")
    c.add(k.esfera("lua_emblema", 0.04, (0.0, -0.16, 1.28), "branco", escala=(1, 0.4, 1), segmentos=8, aneis=5), "Chest")
    c.add(k.esfera("lua_sombra", 0.035, (0.018, -0.17, 1.29), CAPA, escala=(1, 0.4, 1), segmentos=8, aneis=5), "Chest")
    # capa (atrás) e gola alta
    c.add(k.caixa("capa", (0.5, 0.05, 0.7), (0, 0.18, 1.12), CAPA, bevel=0.02, rot=(-8, 0, 0)), "Chest")
    for i, x in enumerate((-0.16, 0.05, 0.18)):
        c.add(k.esfera("estrela_capa", 0.02, (x, 0.21, 0.9 + i * 0.15), "amarelo_sol", segmentos=4, aneis=3), "Chest")
    c.add(k.toro("gola", 0.14, 0.04, (0, 0, 1.45), OUR, seg=12, seg_menor=4), "Chest")
    # telescópio nas costas
    c.add(k.cilindro("telescopio", 0.06, 0.6, (0.05, 0.27, 1.35), OUR, lados=10, rot=(0, 35, 0), raio_topo=0.045), "Chest")
    c.add(k.cilindro("lente_tel", 0.062, 0.02, (0.23, 0.27, 1.6), "lente", lados=10, rot=(0, 35, 0)), "Chest")
    # cabeça planeta, anel e lua
    c.add(k.cilindro("pescoco", 0.055, 0.1, (0, 0, 1.47), "pele_2", lados=8), "Neck")
    c.add(k.esfera("planeta", 0.22, (0, 0, 1.7), PL, segmentos=14, aneis=10), "Head")
    c.add(k.esfera("continente", 0.1, (0.1, -0.12, 1.79), "teal", escala=(1.2, 0.5, 0.7), segmentos=8, aneis=5), "Head")
    c.add(k.esfera("continente2", 0.07, (-0.14, 0.05, 1.62), "teal", escala=(0.6, 1.2, 0.7), segmentos=8, aneis=5), "Head")
    c.add(k.toro("anel", 0.34, 0.022, (0, 0, 1.72), "amarelo_sol", rot=(0, 22, -12), seg=24, seg_menor=4), "Head")
    c.add(k.esfera("lua", 0.05, (-0.33, -0.05, 1.86), "branco", segmentos=8, aneis=6), "Head")
    for s in (1, -1):
        c.add(k.esfera("olho", 0.035, (s * 0.075, -0.2, 1.71), "branco", escala=(0.8, 0.5, 1.1), segmentos=8, aneis=5), "Head")
        c.add(k.esfera("pupila", 0.02, (s * 0.075, -0.218, 1.71), "preto", segmentos=6, aneis=4), "Head")
    c.add(k.caixa("sorriso", (0.07, 0.012, 0.015), (0, -0.21, 1.62), "branco"), "Head")

    def braco(lado, s):
        c.add(k.esfera("ombro", 0.09, (s * 0.24, 0, 1.38), CAPA, segmentos=10, aneis=6), f"{lado}UpperArm")
        c.add(k.cilindro("braco", 0.068, 0.25, (s * 0.35, 0, 1.38), CAPA, lados=8, rot=(0, 90, 0)), f"{lado}UpperArm")
        c.add(k.esfera("cotovelo", 0.062, (s * 0.47, 0, 1.38), CAPA, segmentos=8, aneis=6), f"{lado}LowerArm")
        c.add(k.cilindro("antebraco", 0.063, 0.18, (s * 0.57, 0, 1.38), CAPA, lados=8, rot=(0, 90, 0), raio_topo=0.085), f"{lado}LowerArm")
        c.add(k.toro("punho", 0.08, 0.014, (s * 0.67, 0, 1.38), OUR, rot=(0, 90, 0), seg=10, seg_menor=4), f"{lado}LowerArm")
        c.add(k.esfera("luva", 0.07, (s * 0.77, 0, 1.38), "branco", escala=(1.1, 0.8, 0.95), segmentos=8, aneis=6), f"{lado}Hand")

    def perna(lado, s):
        x = s * 0.11
        c.add(k.cilindro("coxa", 0.098, 0.42, (x, 0, 0.74), "preto", lados=8), f"{lado}UpperLeg")
        c.add(k.esfera("joelho", 0.088, (x, 0, 0.53), "preto", segmentos=8, aneis=6), f"{lado}LowerLeg")
        c.add(k.cilindro("canela", 0.085, 0.24, (x, 0, 0.38), "preto", lados=8), f"{lado}LowerLeg")
        c.add(k.cilindro("bota", 0.1, 0.2, (x, 0, 0.18), PL, lados=8), f"{lado}LowerLeg")
        c.add(k.esfera("estrela_bota", 0.02, (x, -0.1, 0.22), "amarelo_sol", segmentos=4, aneis=3), f"{lado}LowerLeg")
        c.add(k.caixa("pe", (0.17, 0.3, 0.11), (x, -0.05, 0.06), PL, bevel=0.04), f"{lado}Foot")
        c.add(k.caixa("sola", (0.18, 0.31, 0.03), (x, -0.05, 0.015), "preto"), f"{lado}Foot")

    c.lados(braco)
    c.lados(perna)


# =============================================================== GUARDIÃO DA TEMPESTADE
def guardiao(c):
    """Guardião da Tempestade: armadura escura de placas com ombreiras de nuvem
    carregada, elmo com viseira em T luminosa e crista de raio, emblema de raio no
    peito, anel de vento na cintura e capa rasgada."""
    AR, AE, NU, RA = "azul_tormenta", "metal_escuro", "cinza_tecido", "amarelo_sol"

    def nuvem(nome, centro, osso, escala=1.0):
        for dx, dy, dz, r in ((0, 0, 0, 0.09), (0.07, 0.02, -0.02, 0.07), (-0.06, 0.03, -0.01, 0.07),
                              (0.02, -0.06, 0.01, 0.065), (0.0, 0.05, 0.05, 0.06)):
            c.add(k.esfera(nome, r * escala, (centro[0] + dx * escala, centro[1] + dy * escala, centro[2] + dz * escala),
                           NU if r > 0.07 else "branco", segmentos=8, aneis=6), osso)

    c.add(k.caixa("pelve", (0.4, 0.27, 0.22), (0, 0, 0.95), AE, bevel=0.05), "Hips")
    c.add(k.toro("anel_vento", 0.27, 0.014, (0, 0, 1.0), "azul_ceu", rot=(0, 8, 0), seg=20, seg_menor=4), "Hips")
    for s in (1, -1):
        c.add(k.caixa("saiote", (0.16, 0.05, 0.2), (s * 0.12, -0.13, 0.88), AR, bevel=0.02, rot=(8, 0, 0)), "Hips")
    c.add(k.caixa("barriga", (0.4, 0.27, 0.18), (0, 0, 1.13), AE, bevel=0.05), "Spine")
    c.add(k.caixa("peitoral", (0.52, 0.33, 0.33), (0, 0, 1.3), AR, bevel=0.09), "Chest")
    for i, (x, z, r) in enumerate(((0.03, 1.38, 25), (-0.02, 1.3, -25), (0.03, 1.22, 25))):   # raio no peito
        c.add(k.caixa("raio", (0.09, 0.02, 0.035), (x, -0.17, z), RA, rot=(0, r, 0)), "Chest")
    nuvem("nuvem_e", (0.28, 0, 1.48), "LeftUpperArm", 1.15)
    nuvem("nuvem_d", (-0.28, 0, 1.48), "RightUpperArm", 1.15)
    # capa rasgada (pontas em zigue-zague)
    c.add(k.caixa("capa", (0.5, 0.04, 0.55), (0, 0.19, 1.15), "preto", bevel=0.01, rot=(-6, 0, 0)), "Chest")
    for i in range(4):
        c.add(k.caixa("ponta_capa", (0.1, 0.04, 0.16), (-0.18 + i * 0.12, 0.2, 0.84 - (i % 2) * 0.05), "preto", rot=(-6, 0, 45)), "Chest")
    # elmo
    c.add(k.cilindro("pescoco", 0.07, 0.1, (0, 0, 1.47), AE, lados=8), "Neck")
    c.add(k.esfera("elmo", 0.225, (0, 0, 1.69), AR, escala=(1.0, 1.05, 1.08), segmentos=14, aneis=10), "Head")
    c.add(k.caixa("viseira_h", (0.26, 0.02, 0.04), (0, -0.225, 1.72), "azul_ceu"), "Head")
    c.add(k.caixa("viseira_v", (0.045, 0.02, 0.14), (0, -0.225, 1.64), "azul_ceu"), "Head")
    c.add(k.caixa("maxilar", (0.3, 0.14, 0.1), (0, -0.12, 1.53), AE, bevel=0.03), "Head")
    for i, (y, z, r) in enumerate(((0.0, 1.95, 30), (0.06, 2.03, -30), (0.12, 2.11, 30))):   # crista de raio
        c.add(k.caixa("crista", (0.03, 0.11, 0.04), (0, y, z), RA, rot=(r, 0, 0)), "Head")

    def braco(lado, s):
        c.add(k.cilindro("braco", 0.07, 0.25, (s * 0.35, 0, 1.38), AE, lados=8, rot=(0, 90, 0)), f"{lado}UpperArm")
        c.add(k.esfera("cotovelo", 0.07, (s * 0.47, 0, 1.38), AR, segmentos=8, aneis=6), f"{lado}LowerArm")
        c.add(k.cilindro("manopla", 0.085, 0.2, (s * 0.58, 0, 1.38), AR, lados=8, rot=(0, 90, 0), raio_topo=0.07), f"{lado}LowerArm")
        c.add(k.caixa("raio_manopla", (0.08, 0.02, 0.03), (s * 0.58, -0.088, 1.38), RA, rot=(0, 25, 0)), f"{lado}LowerArm")
        c.add(k.esfera("mao", 0.08, (s * 0.78, 0, 1.38), AE, escala=(1.1, 0.85, 0.95), segmentos=10, aneis=6), f"{lado}Hand")

    def perna(lado, s):
        x = s * 0.115
        c.add(k.cilindro("coxa", 0.1, 0.42, (x, 0, 0.74), AE, lados=8), f"{lado}UpperLeg")
        c.add(k.caixa("placa_coxa", (0.13, 0.04, 0.2), (x, -0.09, 0.74), AR, bevel=0.015), f"{lado}UpperLeg")
        c.add(k.esfera("joelheira", 0.095, (x, -0.02, 0.53), AR, segmentos=8, aneis=6), f"{lado}LowerLeg")
        c.add(k.cilindro("greva", 0.095, 0.3, (x, 0, 0.35), AR, lados=8, raio_topo=0.085), f"{lado}LowerLeg")
        c.add(k.caixa("bota", (0.19, 0.33, 0.13), (x, -0.05, 0.065), AE, bevel=0.04), f"{lado}Foot")
        c.add(k.caixa("sola", (0.2, 0.34, 0.03), (x, -0.05, 0.015), "preto"), f"{lado}Foot")

    c.lados(braco)
    c.lados(perna)


SKINS = {
    "capitao_mare_01": capitao_mare,
    "entregador_01": entregador,
    "escafandro_01": escafandro,
    "faz_tudo_01": faz_tudo,
    "espantalho_01": espantalho,
    "explorador_01": explorador,
    "botanico_01": botanico,
    "astronomo_01": astronomo,
    "guardiao_01": guardiao,
}


# =============================================================== ACESSÓRIOS DOS CONJUNTOS
def peixe(asset_id, corpo, listra, nadadeira):
    """Peixinho do aquário do Capitão Maré (~7 cm). Nada pela Godot (TrajeFx)."""
    p = [
        k.esfera("corpo", 0.03, (0, 0, 0), corpo, escala=(0.55, 1.2, 0.85), segmentos=8, aneis=6),
        k.caixa("listra", (0.035, 0.012, 0.05), (0, -0.005, 0), listra, bevel=0.005),
        k.cilindro("cauda", 0.025, 0.035, (0, 0.045, 0), nadadeira, lados=4, rot=(90, 0, 0), raio_topo=0.0),
        k.caixa("barbatana", (0.006, 0.025, 0.018), (0, 0.0, 0.026), nadadeira, rot=(-20, 0, 0)),
    ]
    for s in (1, -1):
        p.append(k.esfera("olho", 0.006, (s * 0.014, -0.022, 0.006), "preto", segmentos=4, aneis=3))
    k.unir(p, asset_id)


def ancora_01():
    """Picareta-âncora do Capitão Maré: segura-se pela haste (argola embaixo, com
    corda enrolada na pega), cepo atravessado, e na ponta de cima a cruz com os
    dois braços curvos e as unhas (patas). A unha da frente é o ponto de impacto.
    Mesmos marcadores da picareta padrão (grip_r, grip_l, cabeca, centro_cabeca):
    só muda a aparência, o gameplay é o mesmo."""
    import gerar_armas as ga
    ME, MC, LT = "metal_escuro", "metal_claro", "dourado"
    p = [
        k.toro("argola", 0.05, 0.014, (0, 0, -0.2), LT, rot=(0, 90, 0), seg=12, seg_menor=4),
        k.cilindro("haste", 0.026, 0.78, (0, 0, 0.21), ME, lados=8),
        k.cilindro("pega", 0.033, 0.24, (0, 0, -0.01), "areia", lados=8),
        k.cilindro("cepo", 0.017, 0.34, (0, 0, 0.3), MC, lados=6, rot=(0, 90, 0)),
        k.esfera("ponta_cepo_e", 0.026, (0.17, 0, 0.3), MC, segmentos=6, aneis=4),
        k.esfera("ponta_cepo_d", 0.026, (-0.17, 0, 0.3), MC, segmentos=6, aneis=4),
        k.esfera("cruz", 0.045, (0, 0, 0.6), ME, segmentos=8, aneis=6),
    ]
    for i in range(3):                                         # corda enrolada
        p.append(k.toro(f"corda{i}", 0.034, 0.009, (0, 0, -0.1 + i * 0.07), "madeira_clara", seg=10, seg_menor=4))
    # braços: arco (semicírculo no plano YZ) saindo da cruz e descendo para os
    # lados; cada braço é feito de segmentos ao longo do arco, e a unha (pata
    # triangular) continua na direção da tangente na ponta
    C, R = 0.42, 0.26
    def ponto(phi, lado):
        return (0.0, lado * R * math.cos(math.radians(phi)), C + R * math.sin(math.radians(phi)))
    for lado in (-1, 1):
        angulos = [90, 74, 58, 43, 30, 18]
        for a0, a1 in zip(angulos, angulos[1:]):
            p0, p1 = ponto(a0, lado), ponto(a1, lado)
            dy, dz = p1[1] - p0[1], p1[2] - p0[2]
            comp = math.hypot(dy, dz)
            meio = (0.0, (p0[1] + p1[1]) / 2, (p0[2] + p1[2]) / 2)
            ang = math.degrees(math.atan2(-dy, dz))
            p.append(k.cilindro(f"braco{lado}{a0}", 0.024, comp + 0.012, meio, ME, lados=6, rot=(ang, 0, 0)))
        fim = ponto(18, lado)
        tang = (0.0, lado * R * math.sin(math.radians(18)), -R * math.cos(math.radians(18)))
        n = math.hypot(tang[1], tang[2])
        t = (0.0, tang[1] / n, tang[2] / n)
        ang = math.degrees(math.atan2(-t[1], t[2]))
        # unha: pirâmide achatada (3 lados) apontando na tangente
        p.append(k.cilindro(f"unha{lado}", 0.06, 0.13, (0.0, fim[1] + t[1] * 0.05, fim[2] + t[2] * 0.05), MC, lados=3,
                            rot=(ang, 0, 0), raio_topo=0.0))
    o = k.unir(p, "ancora_01")
    o["tipo"] = "ferramenta"
    for nome, pos in ga.MARCADORES["picareta_01"].items():
        k.marcador(nome, pos, pai=o)


def _asa(nome, verts, cor, espessura=0.05):
    malha = bpy.data.meshes.new(nome)
    n = len(verts)
    malha.from_pydata(verts, [], [tuple(range(n))])
    o = bpy.data.objects.new(nome, malha)
    bpy.context.scene.collection.objects.link(o)
    bpy.context.view_layer.objects.active = o
    o.select_set(True)
    mod = o.modifiers.new("espessura", "SOLIDIFY")
    mod.thickness = espessura
    bpy.ops.object.modifier_apply(modifier=mod.name)
    k.pintar(o, cor)
    return o


def _barra_planador():
    return [k.cilindro("mastro", 0.03, 1.1, (0, -0.2, -0.5), "metal_escuro", lados=6),
            k.caixa("barra", (1.0, 0.06, 0.06), (0, -0.2, -1.05), "metal_escuro")]


def planador_arraia_01():
    """Planador Arraia (conjunto do Capitão Maré): uma arraia de tecido com as
    costas azul-tormenta pintadas de bolinhas, barriga clara, olhinhos e cauda."""
    p = [_asa("costas", [(0, -1.1, 0.12), (2.3, 0.15, 0.0), (0, 0.85, 0.1), (-2.3, 0.15, 0.0)], "azul_tormenta"),
         _asa("barriga", [(0, -1.0, 0.04), (2.1, 0.15, -0.04), (0, 0.78, 0.03), (-2.1, 0.15, -0.04)], "azul_ceu", 0.03)]
    for x, y in ((0.6, 0.0), (-0.6, 0.0), (1.2, 0.2), (-1.2, 0.2), (0, 0.3), (0.3, -0.5), (-0.3, -0.5)):
        p.append(k.esfera("pinta", 0.08, (x, y, 0.17), "branco", escala=(1, 1, 0.3), segmentos=8, aneis=4))
    for sx in (1, -1):
        p.append(k.esfera("olho", 0.07, (sx * 0.22, -0.95, 0.2), "branco", segmentos=8, aneis=6))
        p.append(k.esfera("pupila", 0.035, (sx * 0.22, -1.0, 0.24), "preto", segmentos=6, aneis=4))
        p.append(k.caixa("barbatana_cab", (0.1, 0.3, 0.06), (sx * 0.3, -1.15, 0.08), "azul_tormenta", rot=(0, 0, sx * 20)))
    p.append(k.cilindro("cauda", 0.04, 1.3, (0, 1.45, 0.08), "azul_tormenta", lados=6, rot=(90, 0, 0), raio_topo=0.005))
    p += _barra_planador()
    k.unir(p, "planador_arraia_01")


def planador_folha_01():
    """Planador Folha (conjunto do Botânico): uma folha enorme com nervuras e talo."""
    pts = []
    for i in range(14):                                       # contorno de folha (losango arredondado)
        a = i / 14 * math.tau
        r = 1.0 + 0.15 * math.cos(2 * a)
        pts.append((math.sin(a) * 2.2 * r, -math.cos(a) * 1.2 * r * (1.25 if math.cos(a) > 0 else 0.9), 0.1 * math.cos(a) ** 2))
    p = [_asa("folha", pts, "folha_media", 0.05),
         k.caixa("nervura", (0.06, 2.6, 0.04), (0, 0.0, 0.12), "folha_escura")]
    for sx in (1, -1):
        for j, y in enumerate((-0.6, 0.0, 0.6)):
            p.append(k.caixa("nervura_lat", (1.4, 0.04, 0.035), (sx * 0.65, y + 0.25, 0.11), "folha_escura", rot=(0, 0, sx * -30)))
    p.append(k.cilindro("talo", 0.04, 0.6, (0, 1.6, 0.1), "folha_escura", lados=6, rot=(80, 0, 0), raio_topo=0.02))
    p += _barra_planador()
    k.unir(p, "planador_folha_01")


ACESSORIOS = {
    # id: (categoria, gerador)
    "peixe_laranja_01": ("mochilas_acessorios", lambda: peixe("peixe_laranja_01", "laranja", "branco", "laranja")),
    "peixe_amarelo_01": ("mochilas_acessorios", lambda: peixe("peixe_amarelo_01", "amarelo_sol", "azul_ceu", "azul_ceu")),
    "ancora_01": ("armas", ancora_01),
    "planador_arraia_01": ("cenario", planador_arraia_01),
    "planador_folha_01": ("cenario", planador_folha_01),
}


def main():
    for asset_id in sys.argv[1:] or list(SKINS) + list(ACESSORIOS):
        k.nova_cena()
        if asset_id in ACESSORIOS:
            cat, ger = ACESSORIOS[asset_id]
            ger()
            k.salvar(cat, asset_id)
        else:
            _montar(asset_id, SKINS[asset_id])
            k.salvar("personagens", asset_id)


if __name__ == "__main__":
    main()
