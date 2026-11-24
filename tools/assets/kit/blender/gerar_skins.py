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

import estilo_personagem as ep  # noqa: E402
import gerar_personagem as gp  # noqa: E402
import kit_comum as k  # noqa: E402

LADOS = (("Left", 1), ("Right", -1))


class Corpo:
    """Coleta as peças, cada uma presa (peso 1) a um osso."""

    def __init__(self):
        self.p = []
        self.escala_cabeca = ep.ESCALA_CABECA

    def add(self, o, osso):
        if osso == "Head":
            ep.escalar_cabeca(o, self.escala_cabeca)
        self.p.append(gp._osso(o, osso))
        return o

    def pele(self, o):
        """Peça com pesos suaves já calculados (corpo, roupas)."""
        self.p.append(o)
        return o

    def roupa(self, objs):
        """Cascas (com pesos) entram como pele; o resto (golas, punhos, bolsos,
        cintos) segue o osso mais perto do seu centro."""
        for o in objs:
            if len(o.vertex_groups) > 0:
                self.pele(o)
            else:
                self.add(o, ep.osso_mais_perto(ep.centro(o)))

    def varios(self, objs, osso):
        for o in objs:
            self.add(o, osso)

    def lados(self, fn):
        for lado, s in LADOS:
            fn(lado, s)


def _montar(asset_id, construir):
    c = Corpo()
    construir(c)
    if os.environ.get("TRIS"):
        cont = {}
        for o in c.p:
            n = o.name.split(".")[0]
            cont[n] = cont.get(n, 0) + sum(len(p.vertices) - 2 for p in o.data.polygons)
        print("TRIS", sorted(cont.items(), key=lambda kv: -kv[1])[:25])
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


# =============================================================== RECRUTA (revisão de arte)
def _oculos_aviador(c, cor_lente="lente", z=1.775, alca="preto", tam=1.0):
    """Óculos de aviador na testa: duas lentes em armação de metal, ponte e alça."""
    for s in (1, -1):
        c.add(k.cilindro("lente", 0.047 * tam, 0.035, (s * 0.068, -0.172, z), cor_lente, lados=14, rot=(80, 0, 0)), "Head")
        c.add(k.toro("aro", 0.05 * tam, 0.012, (s * 0.068, -0.18, z), "metal_escuro", rot=(80, 0, 0), seg=12, seg_menor=4), "Head")
        c.add(k.esfera("brilho_lente", 0.012, (s * 0.068 - 0.015, -0.2, z + 0.02), "branco", segmentos=6, aneis=4), "Head")
    c.add(k.caixa("ponte", (0.04, 0.012, 0.014), (0, -0.188, z + 0.006), "metal_escuro", bevel=0.004), "Head")
    c.add(ep.anel("alca_oculos", 0.176, 0.014, (0, 0.012, z - 0.005), alca, seg=24, rx=0.178, achatado=1.4), "Head")


def _cachecol(c, cor, listra=None):
    """Cachecol de vento: volta no pescoço e duas pontas esvoaçando para trás."""
    c.add(ep.anel("cachecol", 0.085, 0.04, (0, 0.006, 1.445), cor, seg=16, rx=0.095), "Chest")
    c.add(ep.mecha("ponta1", (0.06, -0.06, 1.44), (0.13, 0.25, 1.24), 0.042, cor, curva=(0.03, 0.04, 0.05)), "Chest")
    c.add(ep.mecha("ponta2", (0.03, 0.06, 1.44), (0.0, 0.34, 1.31), 0.036, cor, curva=(-0.02, 0.03, 0.06)), "Chest")
    if listra:
        c.add(ep.anel("listra_cachecol", 0.092, 0.012, (0, 0.006, 1.42), listra, seg=16, rx=0.1), "Chest")


def recruta(c, fem=False):
    """Recruta (traje inicial): camiseta teal com faixa amarela, jeans, cachecol
    coral de vento, óculos de aviador na testa, luvas cinza e botas de couro.
    Recruta Brisa: roxo/verde, cachecol teal, rabo de cavalo, brincos."""
    pele = "pele_1" if fem else "pele_2"
    corpo = ep.montar_humano(c, "fino" if fem else "padrao", pele, "rabo" if fem else "topete", "cabelo_castanho",
                             olhos_cor="teal_escuro" if fem else "azul_tormenta", feminino=fem, sorriso=0.7 if fem else 0.55,
                             labio="coral" if fem else None, sobrancelha_ang=6 if fem else 10)
    camisa = "roxo" if fem else "teal"
    c.roupa(ep.camiseta(corpo, camisa, "curta", barra="teal_escuro" if not fem else "azul_tormenta",
                        listra=(1.22, 1.27, "amarelo_sol") if not fem else (1.17, 1.21, "amarelo_sol")))
    c.roupa(ep.calca(corpo, "verde_militar" if fem else "jeans", "longa", cinto="couro"))
    _cachecol(c, "teal" if fem else "coral")
    _oculos_aviador(c)
    if fem:
        for s in (1, -1):
            c.add(k.esfera("brinco", 0.017, (s * 0.17, -0.0, 1.585), "dourado", segmentos=8, aneis=6), "Head")
    for lado, s in LADOS:
        c.varios(ep.mao(lado, s, "couro", punho="madeira_escura"), f"{lado}Hand")
        c.varios(ep.calcado(lado, s, "couro", sola="madeira_escura", cano=0.12, cadarco="areia"), f"{lado}Foot")


def recruta_brisa(c):
    recruta(c, fem=True)


# =============================================================== utilidades da revisão de arte
def _armadura(corpo, nome, cor, planos, grossura=0.04):
    """Placa de armadura que acompanha o corpo (casca grossa)."""
    return ep.casca(corpo, nome, cor, planos, grossura)


def _juntas(c, cor, r_cot=0.06, r_joe=0.07):
    """Juntas esféricas aparentes (robôs/armaduras)."""
    for lado, s in LADOS:
        c.add(k.esfera("junta_cot", r_cot, (s * 0.47, 0.0, 1.38), cor, segmentos=10, aneis=8), f"{lado}LowerArm")
        c.add(k.esfera("junta_joe", r_joe, (s * 0.11, -0.01, 0.53), cor, segmentos=10, aneis=8), f"{lado}LowerLeg")
        c.add(k.esfera("junta_omb", r_cot * 1.3, (s * 0.24, 0.0, 1.39), cor, segmentos=10, aneis=8), f"{lado}UpperArm")


# =============================================================== CAPITÃO MARÉ
def capitao_mare(c):
    c.escala_cabeca = 1.0          # capacete/aquário já é grande: sem a escala cartum
    """O Aquarista: um aquário de verdade no lugar da cabeça (vidro, moldura, água,
    cascalho, algas, pedra, castelinho, tampa com bomba de ar) sobre um corpo de
    robô: chassi liso de metal com placas rebitadas que acompanham o corpo,
    sanfona na cintura, juntas esféricas, garras e botas de escafandro."""
    vidro = k.material_especial("M_vidro_ventania", (0.8, 0.95, 1.0, 0.2))
    agua = k.material_especial("M_agua_ventania", (0.2, 0.6, 0.95, 0.5))
    ME, MC, LT = "metal_escuro", "metal_claro", "dourado"
    corpo = ep.corpo_base("robusto", ME)
    c.pele(corpo)
    c.pele(_armadura(corpo, "peitoral", MC, ep.entre_z(1.16, 1.43) + ep.ate_x(0.25), 0.045))
    c.pele(_armadura(corpo, "pelve_placa", MC, ep.entre_z(0.86, 1.0) + ep.ate_x(0.25), 0.04))
    for i, z in enumerate((1.03, 1.075, 1.12)):                 # sanfona da cintura
        c.pele(ep.faixa(corpo, f"sanfona{i}", ME if i % 2 else "pedra_escura", ep.entre_z(z - 0.016, z + 0.016), 0.03))
    for lado, s in LADOS:
        c.pele(_armadura(corpo, "braco_placa", MC, ep.braco_entre(s, 0.27, 0.43), 0.035))
        c.pele(_armadura(corpo, "antebraco_placa", MC, ep.braco_entre(s, 0.52, 0.69), 0.04))
        c.pele(ep.faixa(corpo, "faixa_ab", LT, ep.braco_entre(s, 0.6, 0.625), 0.05))
        c.add(k.caixa("ombreira", (0.17, 0.21, 0.07), (s * 0.27, 0, 1.47), MC, bevel=0.025, rot=(0, s * -15, 0)), f"{lado}UpperArm")
        _rebites(c, f"{lado}UpperArm", [(s * 0.27 + dx, dy, 1.5) for dx, dy in ((0.05, -0.07), (-0.05, -0.07))], cor=LT, r=0.012)
        c.add(k.caixa("palma", (0.08, 0.1, 0.09), (s * 0.75, 0, 1.38), ME, bevel=0.02), f"{lado}Hand")
        c.add(k.caixa("garra_f", (0.08, 0.025, 0.035), (s * 0.82, -0.045, 1.36), MC, bevel=0.01, rot=(0, 0, s * 10)), f"{lado}Hand")
        c.add(k.caixa("garra_t", (0.08, 0.025, 0.035), (s * 0.82, 0.045, 1.36), MC, bevel=0.01, rot=(0, 0, s * -10)), f"{lado}Hand")
        c.pele(_armadura(corpo, "coxa_placa", MC, ep.entre_z(0.6, 0.86), 0.03))
        c.pele(_armadura(corpo, "canela_placa", MC, ep.entre_z(0.2, 0.46), 0.035))
        c.add(k.cilindro("pistao_p", 0.016, 0.26, (s * 0.11, 0.085, 0.36), "pedra_escura", lados=6), f"{lado}LowerLeg")
        x = s * 0.11
        c.add(k.caixa("bota", (0.19, 0.32, 0.13), (x, -0.05, 0.065), ME, bevel=0.05), f"{lado}Foot")
        c.add(k.caixa("bico_bota", (0.17, 0.08, 0.1), (x, -0.19, 0.07), LT, bevel=0.035), f"{lado}Foot")
        c.add(k.caixa("sola", (0.18, 0.31, 0.03), (x, -0.05, 0.015), "pedra_escura", bevel=0.01), f"{lado}Foot")
    _juntas(c, LT, 0.058, 0.072)
    c.add(k.caixa("placa_peito", (0.3, 0.03, 0.18), (0, -0.19, 1.27), ME, bevel=0.015), "Chest")
    c.add(k.cilindro("manometro", 0.062, 0.03, (0.06, -0.21, 1.3), "branco", lados=14, rot=(90, 0, 0)), "Chest")
    c.add(k.toro("aro_manometro", 0.064, 0.012, (0.06, -0.225, 1.3), LT, rot=(90, 0, 0), seg=14, seg_menor=4), "Chest")
    c.add(k.caixa("ponteiro", (0.008, 0.01, 0.05), (0.07, -0.23, 1.31), "vermelho", rot=(0, 35, 0)), "Chest")
    c.add(k.caixa("grade", (0.1, 0.02, 0.05), (-0.08, -0.205, 1.24), "preto", bevel=0.005), "Chest")
    _rebites(c, "Chest", [(x, -0.2, z) for x in (-0.15, 0.15) for z in (1.19, 1.37)])
    # tanque de água nas costas, com mangueira até o aquário
    c.add(k.cilindro("tanque", 0.11, 0.38, (0, 0.25, 1.24), MC, lados=14), "Chest")
    c.add(k.esfera("tampa_tanque", 0.11, (0, 0.25, 1.43), LT, escala=(1, 1, 0.45), segmentos=12, aneis=6), "Chest")
    c.add(k.toro("cinta_tanque", 0.113, 0.015, (0, 0.25, 1.18), ME, seg=14, seg_menor=4), "Chest")
    c.add(ep.mecha("mangueira", (0, 0.25, 1.48), (0, 0.15, 1.6), 0.024, "teal", curva=(0, 0.06, 0.06)), "Chest")
    c.add(k.toro("colar", 0.12, 0.035, (0, 0, 1.47), ME, seg=14, seg_menor=5), "Neck")
    c.add(k.cilindro("suporte", 0.07, 0.08, (0, 0, 1.5), MC, lados=10), "Neck")
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



# =============================================================== ENTREGADOR
def entregador(c):
    """Entregador: capacete de moto fechado (viseira escura com reflexo), jaqueta
    acolchoada vermelha com faixas refletivas e gola alta, mochila térmica enorme
    (silhueta quadrada), celular no antebraço, calça cargo e tênis gigantes."""
    J, F, CAL = "vermelho", "amarelo_sol", "cinza_tecido"
    corpo = ep.montar_humano(c, "padrao", "pele_3", None, "preto", sem_cabeca=True)
    c.roupa(ep.jaqueta(corpo, J, gola_alta=True, forro="preto", punho="preto", faixas=[(1.18, F), (1.32, F)]))
    c.roupa(ep.calca(corpo, CAL, "longa", cinto="preto", fivela="metal_claro"))
    for lado, s in LADOS:
        c.add(k.caixa("bolso_cargo", (0.05, 0.13, 0.14), (s * 0.2, 0, 0.72), "pedra_media", bevel=0.02), f"{lado}UpperLeg")
        c.add(k.caixa("aba_cargo", (0.055, 0.135, 0.03), (s * 0.2, 0, 0.8), "pedra_media", bevel=0.01), f"{lado}UpperLeg")
        c.varios(ep.mao(lado, s, "preto", punho=J), f"{lado}Hand")
        c.varios(ep.calcado(lado, s, "branco", sola="laranja", tenis=True, biqueira=J, cadarco="vermelho"), f"{lado}Foot")
    c.add(k.caixa("pochete", (0.2, 0.07, 0.1), (0.06, -0.16, 0.98), "preto", bevel=0.025), "Hips")
    # mochila térmica (logo de vento original)
    c.add(k.caixa("mochila", (0.46, 0.34, 0.46), (0, 0.34, 1.27), "laranja", bevel=0.06), "Chest")
    c.add(k.caixa("tampa_mochila", (0.48, 0.36, 0.05), (0, 0.34, 1.51), F, bevel=0.02), "Chest")
    c.add(k.caixa("costura_mochila", (0.47, 0.35, 0.012), (0, 0.34, 1.07), "coral"), "Chest")
    c.add(k.cilindro("logo", 0.1, 0.012, (0, 0.515, 1.27), "branco", lados=16, rot=(90, 0, 0)), "Chest")
    c.add(k.toro("logo_vento", 0.06, 0.014, (0.01, 0.522, 1.28), "laranja", rot=(90, 0, 0), seg=14, seg_menor=4), "Chest")
    c.add(k.caixa("logo_seta", (0.09, 0.01, 0.02), (0.04, 0.523, 1.24), "laranja", rot=(0, -20, 0)), "Chest")
    for s in (1, -1):
        c.add(k.caixa("alca", (0.05, 0.03, 0.34), (s * 0.12, -0.17, 1.3), "preto", bevel=0.008), "Chest")
    c.add(k.caixa("suporte_cel", (0.11, 0.022, 0.075), (0.6, -0.075, 1.4), "preto", bevel=0.01), "LeftLowerArm")
    c.add(k.caixa("tela_cel", (0.09, 0.008, 0.055), (0.6, -0.088, 1.4), "azul_ceu"), "LeftLowerArm")
    # capacete fechado
    c.add(k.esfera("capacete", 0.245, (0, 0.01, 1.7), J, escala=(1.0, 1.05, 1.02), segmentos=20, aneis=14), "Head")
    c.add(k.esfera("viseira", 0.19, (0, -0.16, 1.71), "preto", escala=(1.0, 0.62, 0.6), segmentos=16, aneis=10), "Head")
    c.add(k.caixa("reflexo_viseira", (0.1, 0.01, 0.025), (-0.06, -0.278, 1.77), "azul_ceu", rot=(0, -15, 0)), "Head")
    c.add(k.caixa("reflexo2", (0.04, 0.01, 0.015), (0.02, -0.28, 1.79), "branco", rot=(0, -15, 0)), "Head")
    c.add(k.caixa("queixeira", (0.26, 0.12, 0.09), (0, -0.14, 1.55), J, bevel=0.04), "Head")
    c.add(k.caixa("respiro", (0.08, 0.01, 0.03), (0, -0.2, 1.55), "preto", bevel=0.008), "Head")
    c.add(k.caixa("listra_cap", (0.05, 0.42, 0.04), (0, 0.02, 1.93), F, bevel=0.012), "Head")
    for s in (1, -1):
        c.add(k.cilindro("tranca", 0.03, 0.02, (s * 0.24, -0.06, 1.68), "metal_escuro", lados=10, rot=(0, 90, 0)), "Head")


# =============================================================== ESCAFANDRO
def escafandro(c):
    c.escala_cabeca = 1.0          # capacete/aquário já é grande: sem a escala cartum
    """Escafandro: mergulhador antigo — capacete de latão gigante (três vigias,
    grade, válvula), corselete rebitado, macacão grosso de lona com costuras,
    pesos de chumbo na cintura e no peito, luvas de couro e botas de chumbo."""
    LAT, LONA, CH = "dourado", "areia", "metal_escuro"
    corpo = ep.montar_humano(c, "robusto", "pele_2", None, "preto", sem_cabeca=True)
    c.pele(ep.casca(corpo, "macacao", LONA, ep.entre_z(0.15, 1.46) + ep.ate_x(0.69), 0.03))
    for lado, s in LADOS:
        c.pele(ep.faixa(corpo, "costura_braco", "madeira_clara", ep.braco_entre(s, 0.44, 0.47), 0.04))
        c.pele(ep.faixa(corpo, "punho_metal", LAT, ep.braco_entre(s, 0.655, 0.69), 0.045))
        c.varios(ep.mao(lado, s, "couro", punho="madeira_escura"), f"{lado}Hand")
        x = s * 0.12
        c.add(k.cilindro("cano_bota", 0.105, 0.14, (x, 0, 0.17), CH, lados=14), f"{lado}LowerLeg")
        c.add(k.caixa("bota", (0.21, 0.34, 0.14), (x, -0.05, 0.07), CH, bevel=0.05), f"{lado}Foot")
        c.add(k.caixa("bico_latao", (0.19, 0.09, 0.11), (x, -0.2, 0.075), LAT, bevel=0.035), f"{lado}Foot")
        c.add(k.caixa("sola", (0.22, 0.35, 0.035), (x, -0.05, 0.017), "pedra_escura", bevel=0.012), f"{lado}Foot")
    c.pele(ep.faixa(corpo, "costura_cintura", "madeira_clara", ep.entre_z(1.08, 1.1) + ep.ate_x(0.3), 0.04))
    c.pele(ep.faixa(corpo, "cinto_peso", "couro", ep.entre_z(0.98, 1.05) + ep.ate_x(0.3), 0.05))
    for x in (-0.12, 0.0, 0.12):
        c.add(k.caixa("peso", (0.08, 0.05, 0.075), (x, -0.2, 1.015), CH, bevel=0.015), "Hips")
    # corselete de latão rebitado
    c.add(k.cilindro("corselete", 0.29, 0.14, (0, 0, 1.43), LAT, lados=20, raio_topo=0.2), "Chest")
    _rebites(c, "Chest", [(math.cos(a) * 0.26, math.sin(a) * 0.26, 1.45) for a in [i * math.tau / 14 for i in range(14)]], cor=CH, r=0.016)
    c.add(k.caixa("peso_peito", (0.2, 0.05, 0.14), (0, -0.24, 1.28), CH, bevel=0.025), "Chest")
    c.add(k.caixa("peso_costas", (0.24, 0.05, 0.18), (0, 0.24, 1.28), CH, bevel=0.025), "Chest")
    # capacete de latão
    c.add(k.esfera("capacete", 0.27, (0, 0, 1.71), LAT, segmentos=22, aneis=16), "Head")
    c.add(k.cilindro("vigia", 0.105, 0.06, (0, -0.255, 1.71), "lente", lados=18, rot=(90, 0, 0)), "Head")
    c.add(k.toro("aro_vigia", 0.11, 0.025, (0, -0.28, 1.71), CH, rot=(90, 0, 0), seg=18, seg_menor=5), "Head")
    c.add(k.esfera("reflexo_vigia", 0.03, (-0.04, -0.3, 1.75), "branco", escala=(1, 0.3, 0.6), segmentos=6, aneis=4), "Head")
    for z in (1.67, 1.71, 1.75):
        c.add(k.caixa("grade_v", (0.17, 0.012, 0.012), (0, -0.29, z), CH), "Head")
    for s in (1, -1):
        c.add(k.cilindro("vigia_lado", 0.07, 0.05, (s * 0.255, 0, 1.72), "lente", lados=14, rot=(0, 90, 0)), "Head")
        c.add(k.toro("aro_lado", 0.075, 0.02, (s * 0.275, 0, 1.72), CH, rot=(0, 90, 0), seg=14, seg_menor=4), "Head")
    c.add(k.cilindro("valvula", 0.05, 0.08, (0, 0.2, 1.88), CH, lados=10, rot=(-40, 0, 0)), "Head")
    c.add(k.toro("volante", 0.05, 0.012, (0, 0.23, 1.92), "vermelho", rot=(-40, 0, 0), seg=12, seg_menor=4), "Head")
    # mangueira de ar: do capacete até o peso das costas (tubo, não lâmina)
    c.add(ep.mecha("mangueira", (0.02, 0.19, 1.6), (0.03, 0.265, 1.34), 0.026, "pedra_escura", curva=(0.02, 0.07, 0.02),
                   lados=8, segmentos=6, cone=False), "Chest")
    c.add(ep.anel("conector", 0.032, 0.012, (0.03, 0.262, 1.36), "dourado", seg=10), "Chest")
    _rebites(c, "Head", [(math.cos(a) * 0.255, math.sin(a) * 0.255, 1.5) for a in [i * math.tau / 10 for i in range(10)]], cor=CH, r=0.018)


# =============================================================== FAZ-TUDO
def faz_tudo(c):
    """Faz-Tudo, o técnico de manutenção: robô amarelo de serviço com cabeça de
    monitor (rosto na tela), antena com giroflex, carcaça com faixas de alerta,
    painel de botões, chave inglesa na mão direita, garra na esquerda e esteiras."""
    AM, ME, MC = "amarelo_sol", "metal_escuro", "metal_claro"
    corpo = ep.corpo_base("padrao", MC)
    c.pele(corpo)
    c.pele(_armadura(corpo, "carcaca", AM, ep.entre_z(1.08, 1.44) + ep.ate_x(0.25), 0.07))
    c.pele(_armadura(corpo, "quadril", ME, ep.entre_z(0.86, 1.0) + ep.ate_x(0.25), 0.04))
    for i in range(4):                                          # faixas de alerta
        c.add(k.caixa("alerta", (0.04, 0.4, 0.09), (-0.18 + i * 0.12, 0, 1.13), "preto", rot=(0, 35, 0)), "Chest")
    c.add(k.caixa("painel", (0.26, 0.02, 0.16), (0, -0.22, 1.3), "preto", bevel=0.012), "Chest")
    for i, cor in enumerate(("vermelho", "folha_clara", "azul_ceu")):
        c.add(k.esfera("botao", 0.022, (-0.07 + i * 0.07, -0.235, 1.34), cor, segmentos=8, aneis=5), "Chest")
    c.add(k.caixa("barra_nivel", (0.18, 0.012, 0.025), (0, -0.235, 1.26), "folha_clara"), "Chest")
    c.add(k.caixa("bateria", (0.3, 0.12, 0.3), (0, 0.26, 1.28), ME, bevel=0.04), "Chest")
    c.add(k.caixa("carga", (0.04, 0.02, 0.18), (0.08, 0.325, 1.28), "folha_clara"), "Chest")
    c.pele(ep.faixa(corpo, "cinto_ferramentas", "couro", ep.entre_z(0.98, 1.04) + ep.ate_x(0.3), 0.05))
    c.add(k.cilindro("chave_fenda", 0.012, 0.16, (0.17, -0.15, 0.98), "vermelho", lados=6, rot=(0, 15, 0)), "Hips")
    c.add(k.cilindro("lanterna", 0.025, 0.1, (-0.18, -0.13, 0.99), "preto", lados=10), "Hips")
    for lado, s in LADOS:
        c.pele(_armadura(corpo, "antebraco", AM, ep.braco_entre(s, 0.5, 0.69), 0.04))
        c.pele(_armadura(corpo, "canela", AM, ep.entre_z(0.22, 0.48), 0.04))
        x = s * 0.12
        c.add(k.caixa("esteira", (0.16, 0.36, 0.13), (x, -0.04, 0.07), ME, bevel=0.06), f"{lado}Foot")
        for dy in (-0.15, -0.04, 0.07):
            c.add(k.cilindro("roda", 0.04, 0.17, (x, dy, 0.065), MC, lados=10, rot=(0, 90, 0)), f"{lado}Foot")
    _juntas(c, ME, 0.055, 0.07)
    c.add(k.caixa("cabo_chave", (0.14, 0.04, 0.03), (-0.76, 0, 1.38), MC, bevel=0.01), "RightHand")
    c.add(k.toro("boca_chave", 0.045, 0.018, (-0.85, 0, 1.38), MC, rot=(90, 0, 0), seg=12, seg_menor=4), "RightHand")
    c.add(k.caixa("pulso", (0.06, 0.09, 0.08), (0.74, 0, 1.38), ME, bevel=0.02), "LeftHand")
    for dy in (-0.035, 0.035):
        c.add(k.caixa("dedo", (0.09, 0.022, 0.03), (0.81, dy, 1.38), AM, bevel=0.01, rot=(0, 0, 12 if dy > 0 else -12)), "LeftHand")
    # cabeça: monitor com rosto, antena com giroflex
    c.add(k.caixa("monitor", (0.42, 0.3, 0.32), (0, 0, 1.69), AM, bevel=0.06), "Head")
    c.add(k.caixa("moldura_tela", (0.36, 0.02, 0.24), (0, -0.15, 1.69), ME, bevel=0.025), "Head")
    c.add(k.caixa("tela", (0.32, 0.02, 0.2), (0, -0.158, 1.69), "preto", bevel=0.02), "Head")
    for s in (1, -1):
        c.add(k.caixa("olho", (0.06, 0.012, 0.07), (s * 0.075, -0.17, 1.715), "azul_ceu", bevel=0.012), "Head")
        c.add(k.caixa("brilho_olho", (0.02, 0.012, 0.02), (s * 0.075 + 0.015, -0.172, 1.735), "branco"), "Head")
        c.add(k.cilindro("orelha", 0.05, 0.05, (s * 0.225, 0, 1.69), ME, lados=12, rot=(0, 90, 0)), "Head")
    c.add(k.toro("boca", 0.045, 0.01, (0, -0.17, 1.66), "azul_ceu", rot=(90, 0, 0), seg=14, seg_menor=4), "Head")
    c.add(k.cilindro("pescoco", 0.05, 0.12, (0, 0, 1.47), ME, lados=10), "Neck")
    c.add(k.cilindro("antena", 0.012, 0.2, (0.12, 0.05, 1.94), ME, lados=6), "Head")
    c.add(k.esfera("giroflex", 0.045, (0.12, 0.05, 2.05), "laranja", escala=(1, 1, 1.2), segmentos=10, aneis=8), "Head")


# =============================================================== ESPANTALHO
def espantalho(c):
    """Espantalho: cabeça de saco de estopa costurada (olhos em X, boca em zigue-
    zague), chapéu de palha de aba larga e torta, camisa xadrez remendada, macacão
    de jeans com alças e botões, palha saindo das mangas, gola e barras, e um corvo."""
    PAL, CAM, MAC = "madeira_clara", "vermelho", "jeans"

    def tufo(nome, pos, rot, osso, n=3, comp=0.09):
        for i in range(n):
            c.add(k.cilindro(nome, 0.018, comp, pos, PAL if i % 2 == 0 else "amarelo_sol", lados=4,
                             rot=(rot[0] + (i - 1) * 18, rot[1] + (i - 1) * 14, rot[2]), raio_topo=0.002), osso)
    corpo = ep.montar_humano(c, "fino", "areia", None, "preto", sem_cabeca=True)
    c.roupa(ep.camiseta(corpo, CAM, "longa", barra="preto"))
    for z in (1.16, 1.3, 1.4):                                   # xadrez (listras escuras)
        c.pele(ep.faixa(corpo, "xadrez", "coral", ep.entre_z(z - 0.012, z + 0.012) + ep.ate_x(0.69), 0.024))
    c.add(k.caixa("remendo", (0.1, 0.02, 0.1), (0.1, -0.17, 1.24), "folha_media", rot=(0, 8, 0), bevel=0.01), "Chest")
    c.add(k.caixa("remendo2", (0.08, 0.02, 0.08), (-0.12, -0.17, 1.38), "azul_ceu", rot=(0, -12, 0), bevel=0.01), "Chest")
    c.roupa(ep.calca(corpo, MAC, "longa", bolsos=False, z_cintura=1.02))
    c.add(k.caixa("peitilho", (0.28, 0.03, 0.2), (0, -0.165, 1.12), MAC, bevel=0.02), "Spine")
    c.add(k.caixa("bolso_peitilho", (0.12, 0.02, 0.08), (0, -0.18, 1.13), "azul_tormenta", bevel=0.01), "Spine")
    for s in (1, -1):
        c.add(k.caixa("alca", (0.055, 0.31, 0.03), (s * 0.11, 0, 1.4), MAC, bevel=0.008, rot=(0, 0, s * 4)), "Chest")
        c.add(k.esfera("botao", 0.02, (s * 0.11, -0.17, 1.22), "dourado", segmentos=8, aneis=5), "Chest")
    tufo("palha_gola", (0, -0.08, 1.46), (-30, 0, 0), "Chest", n=4)
    for lado, s in LADOS:
        tufo("palha_manga", (s * 0.7, 0, 1.38), (0, 90 * s, 0), f"{lado}LowerArm", n=3, comp=0.08)
        tufo("palha_barra", (s * 0.11, 0, 0.18), (180, 0, 0), f"{lado}LowerLeg", n=3, comp=0.07)
        c.add(k.caixa("remendo_joelho", (0.09, 0.02, 0.09), (s * 0.11, -0.1, 0.56), "amarelo_sol", rot=(0, 10, 0), bevel=0.008), f"{lado}LowerLeg")
        c.varios(ep.mao(lado, s, "couro"), f"{lado}Hand")
        c.varios(ep.calcado(lado, s, "couro", sola="madeira_escura", cano=0.08, cadarco="madeira_clara"), f"{lado}Foot")
    # cabeça de estopa: saco amarrado, costuras, olhos em X, boca em zigue-zague
    cab = ep.cabeca("areia", mandibula=0.1, queixo=0.0)
    c.add(cab, "Head")
    c.add(k.toro("corda", 0.075, 0.02, (0, 0.005, 1.54), "madeira_media", seg=12, seg_menor=4), "Head")
    c.add(k.caixa("costura_testa", (0.25, 0.01, 0.012), (0, -0.165, 1.79), "madeira_escura", rot=(0, 4, 0)), "Head")
    for s in (1, -1):
        for r in (45, -45):
            c.add(k.caixa("ponto_olho", (0.07, 0.014, 0.016), (s * 0.068, -0.165, 1.69), "preto", rot=(0, r, 0)), "Head")
    for i in range(5):
        c.add(k.caixa("ponto_boca", (0.04, 0.012, 0.012), (-0.08 + i * 0.04, -0.16, 1.6 + (0.012 if i % 2 else -0.012)), "preto",
                      rot=(0, 30 if i % 2 else -30, 0)), "Head")
    # chapéu de palha de aba larga, torta
    c.add(k.cilindro("aba", 0.36, 0.025, (0, 0.02, 1.84), PAL, lados=20, rot=(-8, 6, 0)), "Head")
    c.add(k.cilindro("copa", 0.15, 0.17, (0, 0.03, 1.94), PAL, lados=14, raio_topo=0.11, rot=(-4, 8, 0)), "Head")
    c.add(k.cilindro("fita", 0.152, 0.035, (0, 0.03, 1.875), "vermelho", lados=14, rot=(-4, 8, 0)), "Head")
    tufo("palha_chapeu", (0.14, 0.05, 1.8), (0, 60, 0), "Head", n=3, comp=0.08)
    # corvo no ombro esquerdo
    c.add(k.esfera("corvo", 0.065, (0.26, 0.02, 1.52), "preto", escala=(0.8, 1.3, 0.9), segmentos=10, aneis=8), "LeftShoulder")
    c.add(k.esfera("corvo_cab", 0.04, (0.26, -0.07, 1.59), "preto", segmentos=10, aneis=8), "LeftShoulder")
    c.add(k.cilindro("bico", 0.014, 0.05, (0.26, -0.115, 1.59), "amarelo_sol", lados=6, rot=(90, 0, 0), raio_topo=0.002), "LeftShoulder")
    c.add(k.esfera("olho_corvo", 0.009, (0.285, -0.095, 1.605), "branco", segmentos=6, aneis=4), "LeftShoulder")
    c.add(k.caixa("rabo_corvo", (0.05, 0.08, 0.015), (0.26, 0.1, 1.5), "preto", rot=(20, 0, 0)), "LeftShoulder")
    # nuca do saco: costura vertical, remendo e palha saindo (não fica um disco liso)
    for i in range(5):
        c.add(k.caixa("costura_nuca", (0.03, 0.008, 0.008), (0, 0.19, 1.6 + i * 0.045), "madeira_escura", rot=(0, 20 * (-1) ** i, 0)), "Head")
    c.add(k.caixa("remendo_nuca", (0.07, 0.01, 0.06), (0.07, 0.178, 1.7), "coral", bevel=0.006, rot=(0, 0, 8)), "Head")
    for i, (x, z) in enumerate(((-0.06, 1.56), (0.0, 1.55), (0.07, 1.565))):
        c.add(k.cilindro("palha_nuca", 0.008, 0.08, (x, 0.17, z), "amarelo_sol", lados=4, rot=(-30, 10 * (i - 1), 0), raio_topo=0.002), "Head")


# =============================================================== EXPLORADOR DAS NUVENS
def explorador(c):
    """Explorador das Nuvens: gorro de aviador de couro com abas, óculos grandes
    no rosto, jaqueta de voo com gola de pelúcia, cachecol comprido ao vento,
    bússola no peito, tubo de mapas e uma mochila-hélice."""
    JQ, CR, PEL = "madeira_media", "couro", "branco"
    corpo = ep.montar_humano(c, "padrao", "pele_2", None, "cabelo_castanho", olhos_cor="madeira_escura", sorriso=0.75)
    c.roupa(ep.jaqueta(corpo, JQ, forro=PEL, punho=PEL))
    c.roupa(ep.calca(corpo, "terra", "longa", cinto=CR))
    for lado, s in LADOS:
        c.add(k.caixa("remendo_asa", (0.08, 0.02, 0.06), (s * 0.35, -0.085, 1.38), "amarelo_sol", bevel=0.008), f"{lado}UpperArm")
        c.varios(ep.mao(lado, s, CR, punho=PEL), f"{lado}Hand")
        c.varios(ep.calcado(lado, s, CR, sola="madeira_escura", cano=0.22, cadarco="madeira_clara"), f"{lado}Foot")
        c.add(k.esfera("joelheira", 0.075, (s * 0.11, -0.05, 0.53), CR, escala=(1, 0.6, 1), segmentos=8, aneis=5), f"{lado}LowerLeg")
    c.add(k.toro("gola_pelucia", 0.12, 0.055, (0, 0.01, 1.45), PEL, seg=12, seg_menor=4), "Chest")
    c.add(k.cilindro("bussola", 0.05, 0.03, (-0.1, -0.19, 1.33), "dourado", lados=14, rot=(90, 0, 0)), "Chest")
    c.add(k.cilindro("mostrador", 0.04, 0.01, (-0.1, -0.207, 1.33), "branco", lados=14, rot=(90, 0, 0)), "Chest")
    c.add(k.caixa("agulha", (0.008, 0.008, 0.05), (-0.1, -0.213, 1.33), "vermelho", rot=(0, 30, 0)), "Chest")
    _cachecol(c, "azul_ceu")
    # mochila-hélice e tubo de mapas
    c.add(k.caixa("motor", (0.24, 0.16, 0.26), (0, 0.26, 1.27), "metal_escuro", bevel=0.05), "Chest")
    c.add(k.cilindro("eixo", 0.025, 0.12, (0, 0.38, 1.3), "metal_claro", lados=8, rot=(90, 0, 0)), "Chest")
    for a in (0, 90):
        c.add(k.caixa("pa_helice", (0.5, 0.012, 0.06), (0, 0.44, 1.3), "madeira_clara", bevel=0.012, rot=(0, a + 20, 0)), "Chest")
    c.add(k.esfera("cubo", 0.035, (0, 0.45, 1.3), "vermelho", segmentos=8, aneis=5), "Chest")
    c.add(k.cilindro("tubo_mapas", 0.045, 0.5, (-0.22, 0.22, 1.25), CR, lados=10, rot=(0, 25, 0)), "Chest")
    # gorro de aviador com abas e óculos grandes sobre os olhos
    gorro = ep.mundo(k.esfera("gorro", 0.19, (0, 0.012, 1.725), CR, escala=(1.02, 1.05, 0.95), segmentos=16, aneis=10))
    import bmesh as _bm
    bm = _bm.new()
    bm.from_mesh(gorro.data)
    _bm.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < 1.66 and v.co.y < 0.0], context="VERTS")
    bm.to_mesh(gorro.data)
    bm.free()
    c.add(gorro, "Head")
    for s in (1, -1):
        c.add(k.caixa("aba_orelha", (0.04, 0.12, 0.16), (s * 0.175, 0.02, 1.6), CR, bevel=0.02, rot=(0, s * 8, 0)), "Head")
        c.add(k.esfera("pelucia_aba", 0.03, (s * 0.19, 0.02, 1.52), PEL, segmentos=8, aneis=5), "Head")
        c.add(k.cilindro("lente", 0.055, 0.04, (s * 0.068, -0.175, 1.69), "lente", lados=12, rot=(85, 0, 0)), "Head")
        c.add(k.toro("aro", 0.058, 0.015, (s * 0.068, -0.186, 1.69), "dourado", rot=(85, 0, 0), seg=16, seg_menor=4), "Head")
        c.add(k.esfera("brilho_lente", 0.012, (s * 0.068 - 0.02, -0.2, 1.71), "branco", segmentos=6, aneis=4), "Head")
    c.add(k.caixa("ponte_oculos", (0.04, 0.02, 0.02), (0, -0.19, 1.7), "dourado", bevel=0.005), "Head")
    c.add(ep.anel("faixa_oculos", 0.18, 0.014, (0, 0.012, 1.69), "preto", seg=24, rx=0.182, achatado=1.4), "Head")


# =============================================================== BOTÂNICO
def botanico(c):
    """Botânico: uma criatura-planta. Corpo de casca de árvore com musgo e vinhas,
    braços de galho com brotos, rosto de madeira com olhos grandes, bochechas
    rosadas e coroa de folhas com uma flor de vento, ombreiras de cogumelo, raízes
    nos pés e um regador."""
    CAS, MAD, FO, FC, FE = "tronco", "madeira_clara", "folha_media", "folha_clara", "folha_escura"
    corpo = ep.corpo_base("padrao", CAS)
    c.pele(corpo)
    c.pele(ep.faixa(corpo, "musgo_cintura", FE, ep.entre_z(0.98, 1.06) + ep.ate_x(0.3), 0.02))
    for i, (x, z, r) in enumerate(((0.1, 1.22, 0.06), (-0.12, 1.33, 0.05), (0.04, 1.4, 0.045), (-0.06, 1.12, 0.04))):
        c.add(k.esfera("musgo", r, (x, -0.135, z), FE if i % 2 else FO, escala=(1, 0.5, 0.8), segmentos=10, aneis=6), "Chest")
    c.add(k.esfera("no_madeira", 0.03, (-0.05, -0.15, 1.2), "madeira_escura", escala=(1, 0.5, 1.3), segmentos=8, aneis=5), "Chest")
    c.add(ep.mecha("vinha", (0.17, -0.08, 1.4), (-0.15, -0.1, 1.05), 0.018, FO, curva=(0.02, -0.09, 0.0), segmentos=6), "Chest")
    for i in range(4):
        c.add(k.esfera("folha_vinha", 0.028, (0.12 - i * 0.09, -0.17, 1.33 - i * 0.09), FC, escala=(1.4, 0.4, 0.7), segmentos=6, aneis=4), "Chest")
    for s in (1, -1):                                           # ombreiras de cogumelo
        c.add(k.esfera("chapeu_cog", 0.11, (s * 0.23, 0, 1.47), "coral", escala=(1, 1, 0.55), segmentos=14, aneis=8), "Chest")
        for dx, dy in ((0.04, -0.05), (-0.03, 0.04), (0.0, 0.0), (0.06, 0.03)):
            c.add(k.esfera("pinta", 0.017, (s * 0.23 + dx, dy, 1.52), "branco", segmentos=6, aneis=4), "Chest")
    c.add(k.cilindro("regador", 0.06, 0.1, (0.2, -0.05, 0.95), "metal_claro", lados=12), "Hips")
    c.add(k.cilindro("bico_regador", 0.012, 0.12, (0.26, -0.1, 0.98), "metal_claro", lados=6, rot=(0, 60, 30)), "Hips")
    for lado, s in LADOS:
        c.add(k.cilindro("broto", 0.012, 0.09, (s * 0.38, 0, 1.44), CAS, lados=5, rot=(0, s * 30, 0), raio_topo=0.002), f"{lado}UpperArm")
        c.add(k.esfera("folhinha", 0.025, (s * 0.4, 0, 1.49), FC, escala=(1.3, 0.5, 0.7), segmentos=6, aneis=4), f"{lado}UpperArm")
        c.varios(ep.mao(lado, s, "madeira_media"), f"{lado}Hand")
        x = s * 0.11
        c.add(k.cilindro("base_raiz", 0.08, 0.1, (x, -0.02, 0.08), CAS, lados=10, raio_topo=0.06), f"{lado}Foot")
        for a in (-50, -15, 20, 140):
            ra = math.radians(a)
            c.add(k.cilindro("raiz", 0.028, 0.16, (x + math.sin(ra) * 0.08, -0.02 - math.cos(ra) * 0.1, 0.035), CAS, lados=6,
                             rot=(80, 0, a), raio_topo=0.008), f"{lado}Foot")
    # rosto de madeira expressivo
    c.add(ep.cabeca(MAD, mandibula=0.12, queixo=0.0, bochecha=0.06), "Head")
    c.varios(ep.cabelo("casca", "tronco"), "Head")             # casca de árvore cobrindo a nuca
    c.varios(ep.olhos(iris="folha_escura", pele=MAD, tam=1.12, palpebra=0.25), "Head")
    c.varios(ep.sobrancelhas(cor="madeira_escura", grossura=0.9, angulo=-6), "Head")
    c.varios(ep.boca(sorriso=0.9, largura=0.045, cor="madeira_escura"), "Head")
    for s in (1, -1):
        c.add(k.esfera("bochecha", 0.025, (s * 0.1, -0.15, 1.615), "coral", escala=(1, 0.4, 0.7), segmentos=8, aneis=5), "Head")
    import random
    rnd = random.Random(3)
    for i in range(12):                                         # coroa de folhas
        a = i / 12 * math.tau
        c.add(k.esfera("folha", 0.065, (math.cos(a) * 0.14, math.sin(a) * 0.13 + 0.02, 1.8 + rnd.uniform(-0.02, 0.03)),
                       FC if i % 2 else FO, escala=(1.3, 0.6, 0.45), segmentos=8, aneis=5, rot=(0, 0, math.degrees(a))), "Head")
    c.add(k.cilindro("caule", 0.012, 0.16, (0.05, 0.04, 1.9), FE, lados=6, rot=(0, 10, 0)), "Head")
    c.add(k.esfera("miolo", 0.035, (0.065, 0.04, 1.99), "amarelo_sol", segmentos=10, aneis=6), "Head")
    for i in range(5):
        a = i / 5 * 360
        c.add(k.caixa("petala", (0.06, 0.012, 0.025), (0.065 + math.cos(math.radians(a)) * 0.05, 0.04, 1.99 + math.sin(math.radians(a)) * 0.05),
                      "rosa", rot=(0, -a, 0), bevel=0.008), "Head")


# =============================================================== ASTRÔNOMO
def astronomo(c):
    """Astrônomo: a cabeça é um pequeno planeta com rosto, anel e uma lua;
    sobretudo longo estrelado com gola dourada, capa, cinto com luneta e um
    telescópio de latão nas costas."""
    PL, CAPA, OUR = "azul_tormenta", "roxo", "dourado"
    corpo = ep.montar_humano(c, "padrao", "pele_2", None, "preto", sem_cabeca=True)
    c.roupa(ep.jaqueta(corpo, CAPA, gola_alta=True, forro=OUR, punho=OUR, ziper=OUR, comprimento=0.66))
    c.roupa(ep.calca(corpo, "preto", "longa", bolsos=False))
    c.pele(ep.faixa(corpo, "cinto", OUR, ep.entre_z(1.0, 1.04) + ep.ate_x(0.3), 0.04))
    c.add(k.cilindro("luneta_cinto", 0.025, 0.18, (-0.21, -0.06, 0.98), OUR, lados=8, rot=(0, 30, 0)), "Hips")
    for i, (x, z) in enumerate(((0.12, 1.36), (-0.1, 1.2), (0.05, 1.12), (-0.15, 1.38), (0.17, 1.2), (-0.12, 0.85), (0.14, 0.78))):
        c.add(k.esfera("estrela", 0.018, (x, -0.19 if z > 1.0 else -0.17, z), "amarelo_sol", segmentos=6, aneis=4), "Chest" if z > 1.0 else "Hips")
    c.add(k.esfera("lua_emblema", 0.04, (0.0, -0.195, 1.28), "branco", escala=(1, 0.4, 1), segmentos=10, aneis=6), "Chest")
    c.add(k.esfera("lua_sombra", 0.035, (0.018, -0.205, 1.29), CAPA, escala=(1, 0.4, 1), segmentos=10, aneis=6), "Chest")
    c.add(k.caixa("capa", (0.5, 0.04, 0.72), (0, 0.2, 1.1), CAPA, bevel=0.02, rot=(-8, 0, 0)), "Chest")
    for i, x in enumerate((-0.16, 0.05, 0.18)):
        c.add(k.esfera("estrela_capa", 0.02, (x, 0.23, 0.9 + i * 0.15), "amarelo_sol", segmentos=6, aneis=4), "Chest")
    c.add(k.cilindro("telescopio", 0.06, 0.6, (0.05, 0.3, 1.35), OUR, lados=12, rot=(0, 35, 0), raio_topo=0.045), "Chest")
    c.add(k.cilindro("lente_tel", 0.062, 0.02, (0.23, 0.3, 1.6), "lente", lados=12, rot=(0, 35, 0)), "Chest")
    for lado, s in LADOS:
        c.varios(ep.mao(lado, s, "branco", punho=OUR), f"{lado}Hand")
        c.varios(ep.calcado(lado, s, PL, sola="preto", cano=0.16, cadarco="amarelo_sol"), f"{lado}Foot")
        c.add(k.esfera("estrela_bota", 0.02, (s * 0.11, -0.07, 0.22), "amarelo_sol", segmentos=6, aneis=4), f"{lado}LowerLeg")
    # cabeça-planeta com rosto
    c.add(k.esfera("planeta", 0.22, (0, 0, 1.7), PL, segmentos=22, aneis=16), "Head")
    c.add(k.esfera("continente", 0.1, (0.1, -0.12, 1.79), "teal", escala=(1.2, 0.5, 0.7), segmentos=10, aneis=6), "Head")
    c.add(k.esfera("continente2", 0.07, (-0.14, 0.05, 1.62), "teal", escala=(0.6, 1.2, 0.7), segmentos=10, aneis=6), "Head")
    c.add(k.toro("anel", 0.34, 0.022, (0, 0, 1.72), "amarelo_sol", rot=(0, 22, -12), seg=28, seg_menor=4), "Head")
    c.add(k.esfera("lua", 0.05, (-0.33, -0.05, 1.86), "branco", segmentos=10, aneis=8), "Head")
    c.varios(ep.olhos(z=1.71, sep=0.075, y_face=-0.195, iris="amarelo_sol", pele=PL, tam=1.05, palpebra=0.28), "Head")
    c.varios(ep.boca(z=1.61, y_face=-0.205, sorriso=0.8, cor="branco"), "Head")


# =============================================================== GUARDIÃO DA TEMPESTADE
def guardiao(c):
    c.escala_cabeca = 1.0          # capacete/aquário já é grande: sem a escala cartum
    """Guardião da Tempestade: armadura escura de placas que acompanham o corpo,
    ombreiras de nuvem carregada, elmo com viseira em T luminosa e crista de raio,
    emblema de raio no peito, anel de vento na cintura e capa rasgada."""
    AR, AE, NU, RA = "azul_tormenta", "metal_escuro", "cinza_tecido", "amarelo_sol"

    def nuvem(nome, centro, osso, escala=1.0):
        for dx, dy, dz, r in ((0, 0, 0, 0.09), (0.07, 0.02, -0.02, 0.07), (-0.06, 0.03, -0.01, 0.07),
                              (0.02, -0.06, 0.01, 0.065), (0.0, 0.05, 0.05, 0.06)):
            c.add(k.esfera(nome, r * escala, (centro[0] + dx * escala, centro[1] + dy * escala, centro[2] + dz * escala),
                           NU if r > 0.07 else "branco", segmentos=10, aneis=8), osso)
    corpo = ep.corpo_base("robusto", AE)
    c.pele(corpo)
    c.pele(_armadura(corpo, "peitoral", AR, ep.entre_z(1.14, 1.44) + ep.ate_x(0.25), 0.05))
    c.pele(_armadura(corpo, "abdomen", AE, ep.entre_z(1.0, 1.14) + ep.ate_x(0.25), 0.035))
    c.pele(ep.faixa(corpo, "anel_vento", "azul_ceu", ep.entre_z(0.99, 1.02) + ep.ate_x(0.3), 0.06))
    for lado, s in LADOS:
        c.pele(_armadura(corpo, "manopla", AR, ep.braco_entre(s, 0.52, 0.69), 0.045))
        c.pele(_armadura(corpo, "coxa_placa", AR, ep.entre_z(0.62, 0.85), 0.035))
        c.pele(_armadura(corpo, "greva", AR, ep.entre_z(0.16, 0.48), 0.045))
        c.add(k.caixa("raio_manopla", (0.08, 0.02, 0.03), (s * 0.6, -0.1, 1.38), RA, rot=(0, 25, 0)), f"{lado}LowerArm")
        c.add(k.caixa("saiote", (0.16, 0.05, 0.2), (s * 0.12, -0.16, 0.88), AR, bevel=0.025, rot=(8, 0, 0)), "Hips")
        c.varios(ep.mao(lado, s, AE, punho=AR), f"{lado}Hand")
        c.varios(ep.calcado(lado, s, AE, sola="preto", biqueira=AR, cano=0.1, cadarco=RA), f"{lado}Foot")
    _juntas(c, AR, 0.06, 0.08)
    for i, (x, z, r) in enumerate(((0.03, 1.38, 25), (-0.02, 1.3, -25), (0.03, 1.22, 25))):
        c.add(k.caixa("raio", (0.09, 0.02, 0.035), (x, -0.205, z), RA, rot=(0, r, 0), bevel=0.006), "Chest")
    nuvem("nuvem_e", (0.28, 0, 1.5), "LeftUpperArm", 1.15)
    nuvem("nuvem_d", (-0.28, 0, 1.5), "RightUpperArm", 1.15)
    # capa: casca das costas (segue o tronco), roxa, com pontas rasgadas penduradas
    c.pele(ep.casca(corpo, "capa", "roxo", ep.entre_z(1.0, 1.46) + ep.ate_x(0.24) + [((0, 0.02, 0), (0, -1, 0))], 0.085))
    for i in range(5):
        x = -0.2 + i * 0.1
        c.add(ep.mecha("ponta_capa", (x, 0.2, 1.04), (x * 1.15, 0.27, 0.8 - (i % 2) * 0.07), 0.045, "roxo",
                       curva=(0, 0.03, 0), lados=4, segmentos=2), "Hips")
    c.add(k.esfera("elmo", 0.225, (0, 0, 1.69), AR, escala=(1.0, 1.05, 1.08), segmentos=22, aneis=16), "Head")
    c.add(k.caixa("viseira_h", (0.26, 0.02, 0.04), (0, -0.228, 1.72), "azul_ceu", bevel=0.006), "Head")
    c.add(k.caixa("viseira_v", (0.045, 0.02, 0.14), (0, -0.228, 1.64), "azul_ceu", bevel=0.006), "Head")
    c.add(k.caixa("maxilar", (0.3, 0.14, 0.1), (0, -0.12, 1.53), AE, bevel=0.035), "Head")
    for i, (y, z, r) in enumerate(((0.0, 1.95, 30), (0.06, 2.03, -30), (0.12, 2.11, 30))):
        c.add(k.caixa("crista", (0.03, 0.11, 0.04), (0, y, z), RA, rot=(r, 0, 0), bevel=0.006), "Head")


SKINS = {
    "recruta_base_01": recruta,
    "recruta_brisa_01": recruta_brisa,
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
