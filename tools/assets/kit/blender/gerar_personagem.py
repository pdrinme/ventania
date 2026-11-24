"""Gera o personagem-base do projeto ("recruta_base_01") com esqueleto padrão
e as animações idle, andar, correr, agachado, agachado_andar, pular, queda,
aterrissar e acenar. Com arma/itens, os braços são guiados por IK na Godot.

Design original: proporções cartunescas (cabeça ~1/4,5 da altura), cachecol
coral (tema vento), óculos de aviador na testa, luvas grossas, botas.

Esqueleto padrão do projeto: nomes do SkeletonProfileHumanoid da Godot, para o
retargeting automático. Todo traje futuro usa ESTE esqueleto.
Pose de repouso: T-pose. Altura ~1,88 m. Frente em -Y no Blender; após a
conversão Y-up do glTF, a Godot recebe o personagem olhando para +Z.

Skinning rígido (cada parte segue um osso com peso 1): barato e estável em
GLES3, combina com o estilo de peças arredondadas.

Uso: python tools/assets/kit/blender/gerar_personagem.py
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy  # noqa: E402
from mathutils import Matrix, Quaternion, Vector  # noqa: E402

import kit_comum as k  # noqa: E402

ASSET_ID = "recruta_base_01"

# (nome, cabeça, cauda, pai) — coordenadas Blender: Z para cima, frente -Y, esquerda +X
OSSOS = [
    ("Root", (0, 0, 0), (0, 0, 0.15), None),
    ("Hips", (0, 0, 0.95), (0, 0, 1.05), "Root"),
    ("Spine", (0, 0, 1.05), (0, 0, 1.2), "Hips"),
    ("Chest", (0, 0, 1.2), (0, 0, 1.4), "Spine"),
    ("Neck", (0, 0, 1.4), (0, 0, 1.5), "Chest"),
    ("Head", (0, 0, 1.5), (0, 0, 1.88), "Neck"),
]
for lado, s in (("Left", 1), ("Right", -1)):
    OSSOS += [
        (f"{lado}Shoulder", (s * 0.05, 0, 1.38), (s * 0.2, 0, 1.38), "Chest"),
        (f"{lado}UpperArm", (s * 0.2, 0, 1.38), (s * 0.47, 0, 1.38), f"{lado}Shoulder"),
        (f"{lado}LowerArm", (s * 0.47, 0, 1.38), (s * 0.72, 0, 1.38), f"{lado}UpperArm"),
        (f"{lado}Hand", (s * 0.72, 0, 1.38), (s * 0.86, 0, 1.38), f"{lado}LowerArm"),
        (f"{lado}UpperLeg", (s * 0.11, 0, 0.95), (s * 0.11, 0, 0.53), "Hips"),
        (f"{lado}LowerLeg", (s * 0.11, 0, 0.53), (s * 0.11, 0, 0.12), f"{lado}UpperLeg"),
        (f"{lado}Foot", (s * 0.11, 0, 0.12), (s * 0.11, -0.16, 0.03), f"{lado}LowerLeg"),
    ]


def _osso(obj, nome_osso):
    g = obj.vertex_groups.new(name=nome_osso)
    g.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
    return obj


# Trajes: todos usam o MESMO esqueleto, as mesmas animações e as mesmas
# proporções de colisão (os cosméticos não mudam a hitbox; ARCHITECTURE §8).
TRAJES = {
    "recruta_base_01": {
        "pele": "pele_2", "camisa": "teal", "faixa": "amarelo_sol", "calca": "jeans", "luva": "cinza_tecido",
        "bota": "couro", "cabelo": "cabelo_castanho", "cachecol": "coral", "feminino": False,
    },
    # Recruta Brisa (Etapa 9, primeiro traje para testar o inventário): mesma
    # identidade (óculos de aviador na testa, cachecol, luvas e botas), com
    # cabelo comprido de rabo de cavalo alto e franja, cílios, lábios coral,
    # brincos e cintura/ombros um pouco mais finos.
    "recruta_brisa_01": {
        "pele": "pele_1", "camisa": "roxo", "faixa": "amarelo_sol", "calca": "verde_militar", "luva": "cinza_tecido",
        "bota": "couro", "cabelo": "cabelo_castanho", "cachecol": "teal", "feminino": True,
    },
}


def _tom_nariz(pele, fem):
    """O nariz acompanha o tom da pele: um tom mais escuro no Recruta e o mesmo tom na Brisa."""
    if fem:
        return pele
    return {"pele_1": "pele_2", "pele_2": "pele_3", "pele_3": "pele_4", "pele_4": "pele_4"}[pele]


def corpo(asset_id=ASSET_ID):
    t = TRAJES[asset_id]
    PELE, CAMISA, CALCA, LUVA, BOTA, CABELO = t["pele"], t["camisa"], t["calca"], t["luva"], t["bota"], t["cabelo"]
    fem = t["feminino"]
    p = []

    def add(o, osso):
        p.append(_osso(o, osso))

    # tronco
    add(k.caixa("pelve", (0.40 if fem else 0.38, 0.25, 0.22), (0, 0, 0.95), CALCA, bevel=0.05), "Hips")
    add(k.caixa("cinto", (0.42 if fem else 0.40, 0.27, 0.05), (0, 0, 1.05), BOTA), "Hips")
    add(k.caixa("fivela", (0.08, 0.02, 0.05), (0, -0.14, 1.05), "dourado"), "Hips")
    add(k.caixa("barriga", (0.31 if fem else 0.36, 0.21 if fem else 0.23, 0.16), (0, 0, 1.14), CAMISA, bevel=0.04), "Spine")
    add(k.caixa("peito", (0.41 if fem else 0.45, 0.27 if fem else 0.28, 0.30), (0, 0, 1.30), CAMISA, bevel=0.07 if fem else 0.06), "Chest")
    add(k.caixa("faixa_peito", (0.42 if fem else 0.46, 0.28 if fem else 0.29, 0.045), (0, 0, 1.25 if not fem else 1.19), t["faixa"]), "Chest")
    # cachecol (preso ao peito, não gira com o pescoço)
    add(k.toro("cachecol", 0.105 if not fem else 0.098, 0.05, (0, 0, 1.45), t["cachecol"], seg=12, seg_menor=6), "Chest")
    add(k.caixa("cachecol_ponta", (0.1, 0.045, 0.3), (0.09, 0.17, 1.31), t["cachecol"], rot=(-12, 0, 8)), "Chest")
    add(k.cilindro("pescoco", 0.055 if fem else 0.06, 0.12, (0, 0, 1.47), PELE, lados=8), "Neck")

    # cabeça
    add(k.esfera("cabeca", 0.2, (0, 0, 1.67), PELE, escala=(1.0, 0.95, 1.05)), "Head")
    if fem:
        # cabelo: calota, laterais até o queixo, franja e rabo de cavalo alto
        add(k.esfera("cabelo", 0.218, (0, 0.03, 1.72), CABELO, escala=(1.04, 1.0, 0.8)), "Head")
        for s in (1, -1):
            add(k.esfera("cabelo_lado", 0.1, (s * 0.165, 0.05, 1.6), CABELO, escala=(0.6, 0.95, 1.55), segmentos=10, aneis=6), "Head")
        add(k.caixa("franja", (0.3, 0.07, 0.07), (0.02, -0.175, 1.8), CABELO, rot=(18, 0, -6), bevel=0.025), "Head")
        add(k.esfera("prendedor", 0.045, (0, 0.185, 1.83), t["cachecol"], segmentos=8, aneis=6), "Head")
        # rabo de cavalo: do prendedor (alto, atrás) caindo para baixo e para trás;
        # +X inclina o topo do cilindro para a frente (-Y), então a base fica atrás
        add(k.cilindro("rabo", 0.042, 0.3, (0, 0.255, 1.69), CABELO, lados=8, rot=(28, 0, 0), raio_topo=0.062), "Head")
        add(k.esfera("rabo_ponta", 0.05, (0, 0.33, 1.545), CABELO, escala=(0.9, 0.9, 1.35), segmentos=8, aneis=6), "Head")
    else:
        add(k.esfera("cabelo", 0.215, (0, 0.025, 1.72), CABELO, escala=(1.03, 1.0, 0.78)), "Head")
        add(k.cilindro("topete", 0.075, 0.16, (0.04, -0.13, 1.86), CABELO, lados=6, rot=(-55, 0, -15), raio_topo=0.0), "Head")
    for s in (1, -1):
        add(k.esfera("olho", 0.036 if fem else 0.034, (s * 0.075, -0.183, 1.665), "preto", escala=(0.8, 0.5, 1.3 if fem else 1.25), segmentos=8, aneis=6), "Head")
        add(k.esfera("brilho", 0.012 if fem else 0.011, (s * 0.075 + 0.01, -0.2, 1.682), "branco", segmentos=6, aneis=4), "Head")
        add(k.esfera("orelha", 0.045, (s * 0.198, 0, 1.655), PELE, escala=(0.5, 1, 1.1), segmentos=8, aneis=6), "Head")
        add(k.cilindro("lente", 0.052, 0.04, (s * 0.075, -0.192, 1.785), "lente", lados=10, rot=(90, 0, 0)), "Head")
        add(k.toro("aro", 0.054, 0.013, (s * 0.075, -0.205, 1.785), "metal_escuro", rot=(90, 0, 0), seg=10, seg_menor=4), "Head")
        if fem:
            # cílios (pequenos traços inclinados para fora) e brincos
            add(k.caixa("cilio", (0.025, 0.012, 0.01), (s * 0.115, -0.178, 1.7), "preto", rot=(0, s * -30, 0)), "Head")
            add(k.caixa("sobrancelha", (0.055, 0.016, 0.014), (s * 0.075, -0.188, 1.72), CABELO, rot=(0, s * -12, 0)), "Head")
            add(k.esfera("brinco", 0.018, (s * 0.205, -0.01, 1.6), "dourado", segmentos=6, aneis=4), "Head")
        else:
            add(k.caixa("sobrancelha", (0.06, 0.02, 0.018), (s * 0.075, -0.186, 1.715), CABELO, rot=(0, s * -8, 0)), "Head")
    add(k.toro("faixa_oculos", 0.207 if not fem else 0.212, 0.018, (0, 0.0, 1.78), "preto", seg=14, seg_menor=4), "Head")
    add(k.esfera("nariz", 0.026 if fem else 0.03, (0, -0.2, 1.625), _tom_nariz(PELE, fem), segmentos=8, aneis=6), "Head")
    if fem:
        add(k.caixa("boca", (0.055, 0.014, 0.018), (0, -0.188, 1.572), "coral", bevel=0.005), "Head")
    else:
        add(k.caixa("boca", (0.065, 0.012, 0.014), (0, -0.188, 1.57), "preto"), "Head")

    # braços (T-pose ao longo de X)
    braco = 0.06 if fem else 0.066
    for lado, s in (("Left", 1), ("Right", -1)):
        add(k.esfera("ombro", 0.08 if fem else 0.088, (s * 0.235, 0, 1.38), CAMISA, segmentos=10, aneis=6), f"{lado}UpperArm")
        add(k.cilindro("braco", braco, 0.25, (s * 0.35, 0, 1.38), CAMISA, lados=8, rot=(0, 90, 0)), f"{lado}UpperArm")
        add(k.esfera("cotovelo", braco - 0.006, (s * 0.47, 0, 1.38), PELE, segmentos=8, aneis=6), f"{lado}LowerArm")
        add(k.cilindro("antebraco", braco - 0.008, 0.22, (s * 0.585, 0, 1.38), PELE, lados=8, rot=(0, 90, 0)), f"{lado}LowerArm")
        add(k.cilindro("punho", 0.066 if fem else 0.068, 0.06, (s * 0.69, 0, 1.38), LUVA, lados=8, rot=(0, 90, 0)), f"{lado}LowerArm")
        add(k.esfera("mao", 0.074 if fem else 0.078, (s * 0.785, 0, 1.38), LUVA, escala=(1.1, 0.8, 0.95), segmentos=10, aneis=6), f"{lado}Hand")
        add(k.esfera("polegar", 0.03 if fem else 0.032, (s * 0.76, -0.062, 1.395), LUVA, segmentos=6, aneis=4), f"{lado}Hand")

        # pernas
        add(k.cilindro("coxa", 0.096 if fem else 0.098, 0.42, (s * 0.11, 0, 0.74), CALCA, lados=8), f"{lado}UpperLeg")
        add(k.esfera("joelho", 0.084 if fem else 0.088, (s * 0.11, 0, 0.53), CALCA, segmentos=8, aneis=6), f"{lado}LowerLeg")
        add(k.cilindro("canela", 0.08 if fem else 0.085, 0.3, (s * 0.11, 0, 0.36), CALCA, lados=8, raio_topo=0.086 if fem else 0.09), f"{lado}LowerLeg")
        add(k.cilindro("cano_bota", 0.1, 0.2 if fem else 0.16, (s * 0.11, 0, 0.19 if fem else 0.17), BOTA, lados=8), f"{lado}LowerLeg")
        if fem:
            add(k.toro("dobra_bota", 0.1, 0.022, (s * 0.11, 0, 0.29), "couro", seg=10, seg_menor=4), f"{lado}LowerLeg")
        add(k.caixa("bota", (0.16 if fem else 0.17, 0.29 if fem else 0.3, 0.12), (s * 0.11, -0.05, 0.07), BOTA, bevel=0.04), f"{lado}Foot")
        add(k.caixa("sola", (0.17 if fem else 0.18, 0.3 if fem else 0.31, 0.03), (s * 0.11, -0.05, 0.015), "preto"), f"{lado}Foot")

    return k.unir(p, asset_id)


def esqueleto():
    dados = bpy.data.armatures.new("esqueleto_padrao")
    arm = bpy.data.objects.new("esqueleto_padrao", dados)
    bpy.context.scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    for nome, cab, cau, pai in OSSOS:
        b = dados.edit_bones.new(nome)
        b.head, b.tail = Vector(cab), Vector(cau)
        b.roll = 0.0
        if pai:
            b.parent = dados.edit_bones[pai]
            b.use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm


def _rot(arm, osso, eixo, graus):
    """Rotação dada em eixos da armadura (relativa ao pai), convertida para o espaço local do osso."""
    m = arm.data.bones[osso].matrix_local.to_3x3()
    r = Quaternion(Vector(eixo), math.radians(graus)).to_matrix()
    return (m.inverted() @ r @ m).to_quaternion()


def _chave(arm, quadro, pose):
    """pose: osso -> [(eixo, graus), ...] (eixos da armadura, aplicados em ordem).
    Chave especial "_quadril": (lado, cima, frente) em metros, desloca o quadril."""
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
        q = Quaternion()
        for eixo, graus in pose.get(pb.name, []):
            q = _rot(arm, pb.name, eixo, graus) @ q
        pb.rotation_quaternion = q
        pb.keyframe_insert("rotation_quaternion", frame=quadro)
    # Hips aponta para +Z: no espaço local do osso, X = lado, Y = cima, Z = -frente
    lado, cima, frente = pose.get("_quadril", (0.0, 0.0, 0.0))
    quadril = arm.pose.bones["Hips"]
    quadril.location = (lado, cima, -frente)
    quadril.keyframe_insert("location", frame=quadro)


X, Y, Z = (1, 0, 0), (0, 1, 0), (0, 0, 1)
#  Convenções (verificadas em render):
#   ossos que apontam para CIMA (Hips/Spine/Chest/Neck/Head): +X inclina para a frente,
#     +Y inclina para a esquerda, +Z gira para a esquerda;
#   ossos que apontam para BAIXO (pernas, braços abaixados): -X leva para a frente;
#   joelho: +X dobra; pé: -X levanta a ponta;
#   braços em T: (Y, +a) abaixa o esquerdo, (Y, -a) abaixa o direito;
#   cotovelo (no referencial do braço): esquerdo (Z, -a), direito (Z, +a) dobra para a frente.


def _mx(v):
    return max(0.0, v)


def _bracos(esq_frente, dir_frente, cot_e, cot_d, abaixar=76.0, abrir=0.0):
    """Braços relaxados ao lado do corpo, balançando para a frente/trás."""
    return {
        "LeftShoulder": [(Y, 4)], "RightShoulder": [(Y, -4)],
        "LeftUpperArm": [(Y, abaixar - abrir), (X, -esq_frente)],
        "RightUpperArm": [(Y, -abaixar + abrir), (X, -dir_frente)],
        "LeftLowerArm": [(Z, -cot_e)], "RightLowerArm": [(Z, cot_d)],
        "LeftHand": [(Z, -8)], "RightHand": [(Z, 8)],
    }


def _pose_idle(t):
    """4 s: respiração e transferência de peso suave entre as pernas."""
    f = t * 2 * math.pi
    resp = math.sin(f * 3)                 # 3 respirações por ciclo
    peso = math.sin(f)                     # 1 transferência de peso por ciclo
    p = {
        # contrapposto: peso mais na perna direita, bacia caída para o outro lado
        "_quadril": (-0.022 + 0.014 * peso, -0.014 + 0.004 * resp, 0.0),
        "Hips": [(Y, 3.0 - 1.6 * peso), (Z, 4.0)],
        "Spine": [(X, 1.0 + 0.8 * resp), (Y, -1.5 + 1.2 * peso), (Z, -3.0)],
        "Chest": [(X, -1.5 * resp), (Y, -1.5 + 0.8 * peso), (Z, -2.0)],
        "Neck": [(X, 1.0)],
        "Head": [(X, 2.0 + 1.2 * math.sin(f * 2 + 0.6)), (Z, -4.0 + 4.0 * math.sin(f + 1.1)), (Y, 3.0)],
        "LeftUpperLeg": [(Y, -3.0 + 1.5 * peso), (X, -5), (Z, 6)], "RightUpperLeg": [(Y, -2.0 + 1.5 * peso), (X, -1)],
        "LeftLowerLeg": [(X, 10 + 3 * _mx(-peso))], "RightLowerLeg": [(X, 3 + 2 * _mx(peso))],
        "LeftFoot": [(X, -2)], "RightFoot": [(X, -2)],
    }
    p.update(_bracos(4 + 1.5 * resp, 4 - 1.5 * resp, 14, 14))
    return p


def _passada(t, perna, joelho, braco, cotovelo, inclinacao, bob, quadril_base=0.0, giro=5.0, voo=0.0):
    """Ciclo de passada com contato do calcanhar, empurrão da ponta, bob do quadril,
    giro da bacia/tronco em oposição e braços contrários às pernas (cotovelo atrasado)."""
    f = t * 2 * math.pi
    s, c = math.sin(f), math.cos(f)
    coxa_e, coxa_d = -perna * s, perna * s                      # negativo = à frente
    joelho_e = 6 + joelho * _mx(c) ** 1.5 + 8 * _mx(math.sin(f - 0.5))
    joelho_d = 6 + joelho * _mx(-c) ** 1.5 + 8 * _mx(math.sin(f + math.pi - 0.5))
    pe_e = -14 * _mx(s) + 26 * _mx(-math.sin(f + 0.5))
    pe_d = -14 * _mx(-s) + 26 * _mx(math.sin(f + 0.5))
    p = {
        # quadril mais baixo no contato (|sin| = 1) e mais alto no apoio; em corrida há voo
        "_quadril": (0.02 * c, quadril_base - bob * abs(s) + voo * abs(c), 0.0),
        "Hips": [(Z, -giro * s), (Y, 2.5 * c)],
        "Spine": [(X, inclinacao * 0.4), (Z, giro * 0.5 * s)],
        "Chest": [(X, inclinacao * 0.6), (Z, giro * 0.9 * s)],
        "Neck": [(X, -inclinacao * 0.35)],
        "Head": [(X, -inclinacao * 0.45 + 1.5 * math.sin(2 * f)), (Z, -giro * 0.3 * s)],
        "LeftUpperLeg": [(X, coxa_e)], "RightUpperLeg": [(X, coxa_d)],
        "LeftLowerLeg": [(X, joelho_e)], "RightLowerLeg": [(X, joelho_d)],
        "LeftFoot": [(X, pe_e)], "RightFoot": [(X, pe_d)],
    }
    atraso = 0.35
    p.update(_bracos(braco * math.sin(f - atraso), -braco * math.sin(f - atraso),
                     cotovelo + 0.5 * cotovelo * _mx(math.sin(f - atraso)),
                     cotovelo + 0.5 * cotovelo * _mx(-math.sin(f - atraso)),
                     abaixar=74.0 if cotovelo < 40 else 68.0))
    return p


def _pose_andar(t):
    return _passada(t, perna=27, joelho=60, braco=24, cotovelo=18, inclinacao=4, bob=0.04, giro=7.0)


def _pose_correr(t):
    return _passada(t, perna=48, joelho=105, braco=50, cotovelo=84, inclinacao=16, bob=0.035,
                    quadril_base=-0.05, giro=11.0, voo=0.045)


def _pose_agachado(t, passo=0.0):
    f = t * 2 * math.pi
    s = math.sin(f)
    resp = math.sin(f * 2)
    p = {
        "_quadril": (0.01 * math.cos(f) * (passo > 0), -0.44 - 0.02 * abs(s) * (passo > 0), 0.04),
        "Hips": [(X, 8), (Z, -3 * s * (passo > 0))],
        "Spine": [(X, 10 + resp)], "Chest": [(X, 10 - resp)],
        "Neck": [(X, -8)], "Head": [(X, -10)],
        "LeftUpperLeg": [(X, -78 - passo * s)], "RightUpperLeg": [(X, -78 + passo * s)],
        "LeftLowerLeg": [(X, 118 + 0.6 * passo * _mx(math.cos(f)))], "RightLowerLeg": [(X, 118 + 0.6 * passo * _mx(-math.cos(f)))],
        "LeftFoot": [(X, -38)], "RightFoot": [(X, -38)],
    }
    p.update(_bracos(18 + 0.5 * passo * s, 18 - 0.5 * passo * s, 40, 40, abaixar=68.0))
    return p


def _pose_pulo(t):
    """t 0..1: impulso (pernas estendidas, braços para cima) -> encolhe no ápice."""
    e = t * t * (3 - 2 * t)
    p = {
        "_quadril": (0, 0.02 * (1 - e), 0),
        "Spine": [(X, -4 + 8 * e)], "Chest": [(X, -6 + 10 * e)], "Head": [(X, 6 - 8 * e)],
        "LeftUpperLeg": [(X, 8 - 50 * e)], "RightUpperLeg": [(X, 4 - 20 * e)],
        "LeftLowerLeg": [(X, 6 + 74 * e)], "RightLowerLeg": [(X, 6 + 46 * e)],
        "LeftFoot": [(X, 30 - 30 * e)], "RightFoot": [(X, 30 - 20 * e)],
    }
    p.update(_bracos(40 - 15 * e, 30 - 10 * e, 30, 30, abaixar=40 + 20 * e))
    return p


def _pose_queda(t):
    f = t * 2 * math.pi
    o = math.sin(f) * 5
    p = {
        "Spine": [(X, 2)], "Chest": [(X, -3 + o * 0.3)], "Head": [(X, 6)],
        "LeftUpperLeg": [(X, -30 + o)], "RightUpperLeg": [(X, -12 - o)],
        "LeftLowerLeg": [(X, 48)], "RightLowerLeg": [(X, 30)],
        "LeftFoot": [(X, 10)], "RightFoot": [(X, 12)],
    }
    p.update(_bracos(10 + o, 6 - o, 26, 26, abaixar=36.0, abrir=0.0))
    return p


def _pose_aterrissar(t):
    """t 0..1: amortece (desce rápido), depois volta à pose de pé."""
    d = math.sin(min(1.0, t / 0.3) * math.pi / 2) if t < 0.3 else 1.0 - ((t - 0.3) / 0.7) ** 1.5
    p = {
        "_quadril": (0, -0.26 * d, 0.02 * d),
        "Hips": [(X, 10 * d)], "Spine": [(X, 10 * d)], "Chest": [(X, 10 * d)], "Head": [(X, -14 * d)],
        "LeftUpperLeg": [(X, -48 * d)], "RightUpperLeg": [(X, -44 * d)],
        "LeftLowerLeg": [(X, 6 + 82 * d)], "RightLowerLeg": [(X, 6 + 78 * d)],
        "LeftFoot": [(X, -36 * d)], "RightFoot": [(X, -34 * d)],
    }
    p.update(_bracos(14 * d, 14 * d, 14 + 25 * d, 14 + 25 * d, abaixar=76 - 22 * d))
    return p


# ---------------------------------------------------------------- entrada na partida
# Poses no referencial do corpo EM PÉ. A orientação do corpo no ar (deitado na
# queda livre, de cabeça para baixo no mergulho, inclinado nas curvas) é aplicada
# na Godot pelo PawnVisual, a partir da velocidade que já vem pela rede.

def _pose_preparar(t):
    """2 s: agachado na porta do ônibus, mão direita no batente, olhando para fora."""
    f = t * 2 * math.pi
    resp = math.sin(f * 2)
    p = {
        "_quadril": (0.0, -0.2 - 0.01 * resp, 0.02),
        "Hips": [(X, 6)], "Spine": [(X, 10 + resp)], "Chest": [(X, 8 - resp)],
        "Neck": [(X, -6)], "Head": [(X, -10), (Z, 6 * math.sin(f))],
        "LeftUpperLeg": [(X, -48)], "RightUpperLeg": [(X, -30)],
        "LeftLowerLeg": [(X, 78)], "RightLowerLeg": [(X, 52)],
        "LeftFoot": [(X, -26)], "RightFoot": [(X, -18)],
    }
    p.update(_bracos(30 + 3 * resp, 0, 40, 0))
    p["RightUpperArm"] = [(Y, 45), (X, -25)]             # segura o batente, no alto
    p["RightLowerArm"] = [(Z, 60)]
    return p


def _pose_saltar(t):
    """0,6 s: impulso para fora (pernas estendem, braços sobem) e abre em X."""
    e = t * t * (3 - 2 * t)
    abre = max(0.0, (t - 0.45) / 0.55)
    p = {
        "_quadril": (0.0, -0.15 * (1 - e), 0.0),
        "Spine": [(X, 8 - 20 * e)], "Chest": [(X, 6 - 12 * e)], "Head": [(X, -6 - 14 * e)],
        "LeftUpperLeg": [(X, -40 * (1 - e) + 12 * e), (Y, -16 * abre)],
        "RightUpperLeg": [(X, -20 * (1 - e) + 18 * e), (Y, 16 * abre)],
        "LeftLowerLeg": [(X, 60 * (1 - e) + 40 * e)], "RightLowerLeg": [(X, 30 * (1 - e) + 50 * e)],
        "LeftFoot": [(X, 10)], "RightFoot": [(X, 10)],
    }
    p.update(_bracos(-30 * e, -30 * e, 30, 30, abaixar=70 - 85 * e))
    return p


def _pose_queda_livre(t):
    """1,6 s: braços e pernas abertos (X), arqueado, com oscilação e "bater" das pernas."""
    f = t * 2 * math.pi
    o = math.sin(f)
    o2 = math.sin(f * 2 + 0.7)
    p = {
        "_quadril": (0.0, 0.0, 0.0),
        "Hips": [(Z, 3 * o)], "Spine": [(X, -14 + 2 * o2), (Y, 2 * o)], "Chest": [(X, -10 - 2 * o2)],
        "Neck": [(X, -14)], "Head": [(X, -22 + 3 * o2), (Z, 5 * o)],
        "LeftUpperLeg": [(Y, -24 - 4 * o), (X, 18 + 6 * o2)], "RightUpperLeg": [(Y, 24 - 4 * o), (X, 18 - 6 * o2)],
        "LeftLowerLeg": [(X, 62 + 10 * o2)], "RightLowerLeg": [(X, 62 - 10 * o2)],
        "LeftFoot": [(X, 24)], "RightFoot": [(X, 24)],
        "LeftShoulder": [(Y, -6)], "RightShoulder": [(Y, 6)],
        "LeftUpperArm": [(Y, -6 + 6 * o), (X, -24)], "RightUpperArm": [(Y, 6 + 6 * o), (X, -24)],
        "LeftLowerArm": [(Z, -40 - 8 * o2)], "RightLowerArm": [(Z, 40 + 8 * o2)],
        "LeftHand": [(Z, -12)], "RightHand": [(Z, 12)],
    }
    return p


def _pose_mergulho(t):
    """1,2 s: braços colados para trás, pernas juntas e esticadas, cabeça olhando à frente."""
    f = t * 2 * math.pi
    o = math.sin(f * 2)
    p = {
        "Spine": [(X, -4)], "Chest": [(X, -6)], "Neck": [(X, -22)], "Head": [(X, -30 + 2 * o)],
        "LeftUpperLeg": [(Y, -3), (X, 4 + 3 * o)], "RightUpperLeg": [(Y, 3), (X, 4 - 3 * o)],
        "LeftLowerLeg": [(X, 10 + 4 * o)], "RightLowerLeg": [(X, 10 - 4 * o)],
        "LeftFoot": [(X, 34)], "RightFoot": [(X, 34)],
        "LeftUpperArm": [(Y, 78), (X, 30 + 2 * o)], "RightUpperArm": [(Y, -78), (X, 30 - 2 * o)],
        "LeftLowerArm": [(Z, -6)], "RightLowerArm": [(Z, 6)],
        "LeftHand": [(Z, -10)], "RightHand": [(Z, 10)],
    }
    return p


def _pose_planador_abrir(t):
    """0,45 s: da queda livre para as mãos na barra (os braços sobem)."""
    e = t * t * (3 - 2 * t)
    a = _pose_queda_livre(0.0)
    b = _pose_planador(0.0)
    return _mistura(a, b, e)


def _pose_planador(t):
    """2 s: pendurado na barra, pernas soltas balançando como pêndulo."""
    f = t * 2 * math.pi
    s = math.sin(f)
    p = {
        "Spine": [(X, 2)], "Chest": [(X, -4)], "Neck": [(X, -6)], "Head": [(X, -8), (Z, 6 * math.sin(f + 1.0))],
        "LeftUpperLeg": [(X, -12 + 10 * s), (Y, -4)], "RightUpperLeg": [(X, -6 - 10 * s), (Y, 4)],
        "LeftLowerLeg": [(X, 22 + 8 * max(0.0, s))], "RightLowerLeg": [(X, 18 + 8 * max(0.0, -s))],
        "LeftFoot": [(X, 16)], "RightFoot": [(X, 16)],
        "LeftUpperArm": [(Y, -62), (X, -10)], "RightUpperArm": [(Y, 62), (X, -10)],
        "LeftLowerArm": [(Z, -34)], "RightLowerArm": [(Z, 34)],
    }
    return p


def _pose_aterrissar_pesado(t):
    """1,0 s: impacto (agacha fundo, mão esquerda no chão) e recuperação até ficar de pé."""
    if t < 0.22:
        d = math.sin(t / 0.22 * math.pi / 2)
    else:
        d = max(0.0, 1.0 - ((t - 0.22) / 0.78) ** 1.4)
    p = {
        "_quadril": (0, -0.5 * d, 0.06 * d),
        "Hips": [(X, 14 * d)], "Spine": [(X, 18 * d)], "Chest": [(X, 12 * d)], "Head": [(X, -18 * d)],
        "LeftUpperLeg": [(X, -86 * d)], "RightUpperLeg": [(X, -40 * d), (Y, 10 * d)],
        "LeftLowerLeg": [(X, 6 + 120 * d)], "RightLowerLeg": [(X, 6 + 96 * d)],
        "LeftFoot": [(X, -40 * d)], "RightFoot": [(X, -30 * d)],
    }
    p.update(_bracos(10 * d, 40 * d, 14 + 10 * d, 14 + 30 * d, abaixar=76 - 4 * d))
    p["LeftUpperArm"] = [(Y, 76 - 6 * d), (X, -48 * d)]           # mão de apoio no chão
    return p


def _mistura(a, b, k):
    """Interpola duas poses (lista de rotações por osso) de forma simples: soma ponderada dos ângulos."""
    out = {}
    for osso in set(a) | set(b):
        if osso == "_quadril":
            qa, qb = a.get(osso, (0, 0, 0)), b.get(osso, (0, 0, 0))
            out[osso] = tuple(qa[i] * (1 - k) + qb[i] * k for i in range(3))
            continue
        out[osso] = [(e, g * (1 - k)) for e, g in a.get(osso, [])] + [(e, g * k) for e, g in b.get(osso, [])]
    return out


def _acao(arm, nome, quadros, pose_fn, passo=2, loop=True):
    """Cria uma ação amostrando a pose a cada `passo` quadros. Em loop, a última
    chave repete a primeira (sem salto na emenda)."""
    acao = bpy.data.actions.new(nome)
    arm.animation_data.action = acao
    n = max(2, quadros // passo)
    for i in range(n + 1):
        t = (i / n) % 1.0 if loop else i / n
        _chave(arm, 1 + round(i * quadros / n), pose_fn(t))
    return acao


def animar(arm):
    arm.animation_data_create()
    import animacoes as an
    # locomoção, pulo, queda, aterrissagem, agachado, eliminação e reações das
    # armas: autoria pose a pose (animacoes.py, revisão 1.4)
    acoes = an.criar_todas(arm) + [
        # entrada na partida (Ônibus de Batalha)
        _acao(arm, "preparar-loop", 60, _pose_preparar, passo=4),
        _acao(arm, "saltar", 18, _pose_saltar, loop=False),
        _acao(arm, "queda_livre-loop", 48, _pose_queda_livre, passo=3),
        _acao(arm, "mergulho-loop", 36, _pose_mergulho, passo=3),
        _acao(arm, "planador_abrir", 14, _pose_planador_abrir, loop=False),
        _acao(arm, "planador-loop", 60, _pose_planador, passo=4),
        _acao(arm, "aterrissar_pesado", 30, _pose_aterrissar_pesado, loop=False),
    ]

    acenar = bpy.data.actions.new("acenar")
    arm.animation_data.action = acenar
    base = _pose_idle(0)
    _chave(arm, 1, base)
    for q, balanco in ((8, 0), (14, 22), (20, -10), (26, 22), (32, -10), (38, 0)):
        pose = dict(base)
        pose["RightUpperArm"] = [(Y, 55)]
        pose["RightLowerArm"] = [(Y, 45 + balanco)]
        pose["Head"] = [(Z, -6), (Y, -4)]
        _chave(arm, q, pose)
    _chave(arm, 46, base)
    acoes.append(acenar)

    for a in acoes:
        a.use_fake_user = True
        trilha = arm.animation_data.nla_tracks.new()
        trilha.name = a.name
        trilha.strips.new(a.name, 1, a)
    arm.animation_data.action = None
    for pb in arm.pose.bones:
        pb.rotation_quaternion = Quaternion()
        pb.location = (0.0, 0.0, 0.0)


def personagem(asset_id):
    malha = corpo(asset_id)
    arm = esqueleto()
    malha.parent = arm
    mod = malha.modifiers.new("esqueleto", "ARMATURE")
    mod.object = arm
    malha["traje"] = asset_id
    animar(arm)
    bpy.context.scene.frame_start, bpy.context.scene.frame_end = 1, 61


GERADORES = {i: (lambda i=i: personagem(i)) for i in TRAJES}


def main():
    for asset_id in sys.argv[1:] or list(GERADORES):
        k.nova_cena()
        GERADORES[asset_id]()
        k.salvar("personagens", asset_id)


if __name__ == "__main__":
    main()
