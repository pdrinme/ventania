"""Gera o personagem-base do projeto ("recruta_base_01") com esqueleto padrão
e as animações idle, acenar, andar, correr, agachado, agachado_andar e no_ar.

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
PELE = "pele_2"
CAMISA = "teal"
CALCA = "jeans"
LUVA = "cinza_tecido"
BOTA = "couro"
CABELO = "cabelo_castanho"

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


def corpo():
    p = []

    def add(o, osso):
        p.append(_osso(o, osso))

    # tronco
    add(k.caixa("pelve", (0.38, 0.25, 0.22), (0, 0, 0.95), CALCA, bevel=0.05), "Hips")
    add(k.caixa("cinto", (0.40, 0.27, 0.05), (0, 0, 1.05), BOTA), "Hips")
    add(k.caixa("fivela", (0.08, 0.02, 0.05), (0, -0.14, 1.05), "dourado"), "Hips")
    add(k.caixa("barriga", (0.36, 0.23, 0.16), (0, 0, 1.14), CAMISA, bevel=0.04), "Spine")
    add(k.caixa("peito", (0.45, 0.28, 0.30), (0, 0, 1.30), CAMISA, bevel=0.06), "Chest")
    add(k.caixa("faixa_peito", (0.46, 0.29, 0.045), (0, 0, 1.25), "amarelo_sol"), "Chest")
    # cachecol (preso ao peito, não gira com o pescoço)
    add(k.toro("cachecol", 0.105, 0.05, (0, 0, 1.45), "coral", seg=12, seg_menor=6), "Chest")
    add(k.caixa("cachecol_ponta", (0.1, 0.045, 0.3), (0.09, 0.17, 1.31), "coral", rot=(-12, 0, 8)), "Chest")
    add(k.cilindro("pescoco", 0.06, 0.12, (0, 0, 1.47), PELE, lados=8), "Neck")

    # cabeça
    add(k.esfera("cabeca", 0.2, (0, 0, 1.67), PELE, escala=(1.0, 0.95, 1.05)), "Head")
    add(k.esfera("cabelo", 0.215, (0, 0.025, 1.72), CABELO, escala=(1.03, 1.0, 0.78)), "Head")
    add(k.cilindro("topete", 0.075, 0.16, (0.04, -0.13, 1.86), CABELO, lados=6, rot=(-55, 0, -15), raio_topo=0.0), "Head")
    for s in (1, -1):
        add(k.esfera("olho", 0.034, (s * 0.075, -0.183, 1.665), "preto", escala=(0.8, 0.5, 1.25), segmentos=8, aneis=6), "Head")
        add(k.esfera("brilho", 0.011, (s * 0.075 + 0.01, -0.199, 1.68), "branco", segmentos=6, aneis=4), "Head")
        add(k.esfera("orelha", 0.045, (s * 0.198, 0, 1.655), PELE, escala=(0.5, 1, 1.1), segmentos=8, aneis=6), "Head")
        add(k.cilindro("lente", 0.052, 0.04, (s * 0.075, -0.192, 1.785), "lente", lados=10, rot=(90, 0, 0)), "Head")
        add(k.toro("aro", 0.054, 0.013, (s * 0.075, -0.205, 1.785), "metal_escuro", rot=(90, 0, 0), seg=10, seg_menor=4), "Head")
        add(k.caixa("sobrancelha", (0.06, 0.02, 0.018), (s * 0.075, -0.186, 1.715), CABELO, rot=(0, s * -8, 0)), "Head")
    add(k.toro("faixa_oculos", 0.207, 0.018, (0, 0.0, 1.78), "preto", seg=14, seg_menor=4), "Head")
    add(k.esfera("nariz", 0.03, (0, -0.2, 1.625), "pele_3", segmentos=8, aneis=6), "Head")
    add(k.caixa("boca", (0.065, 0.012, 0.014), (0, -0.188, 1.57), "preto"), "Head")

    # braços (T-pose ao longo de X)
    for lado, s in (("Left", 1), ("Right", -1)):
        add(k.esfera("ombro", 0.088, (s * 0.24, 0, 1.38), CAMISA, segmentos=10, aneis=6), f"{lado}UpperArm")
        add(k.cilindro("braco", 0.066, 0.25, (s * 0.35, 0, 1.38), CAMISA, lados=8, rot=(0, 90, 0)), f"{lado}UpperArm")
        add(k.esfera("cotovelo", 0.06, (s * 0.47, 0, 1.38), PELE, segmentos=8, aneis=6), f"{lado}LowerArm")
        add(k.cilindro("antebraco", 0.058, 0.22, (s * 0.585, 0, 1.38), PELE, lados=8, rot=(0, 90, 0)), f"{lado}LowerArm")
        add(k.cilindro("punho", 0.068, 0.06, (s * 0.69, 0, 1.38), LUVA, lados=8, rot=(0, 90, 0)), f"{lado}LowerArm")
        add(k.esfera("mao", 0.078, (s * 0.785, 0, 1.38), LUVA, escala=(1.1, 0.8, 0.95), segmentos=10, aneis=6), f"{lado}Hand")
        add(k.esfera("polegar", 0.032, (s * 0.76, -0.065, 1.395), LUVA, segmentos=6, aneis=4), f"{lado}Hand")

        # pernas
        add(k.cilindro("coxa", 0.098, 0.42, (s * 0.11, 0, 0.74), CALCA, lados=8), f"{lado}UpperLeg")
        add(k.esfera("joelho", 0.088, (s * 0.11, 0, 0.53), CALCA, segmentos=8, aneis=6), f"{lado}LowerLeg")
        add(k.cilindro("canela", 0.085, 0.3, (s * 0.11, 0, 0.36), CALCA, lados=8, raio_topo=0.09), f"{lado}LowerLeg")
        add(k.cilindro("cano_bota", 0.1, 0.16, (s * 0.11, 0, 0.17), BOTA, lados=8), f"{lado}LowerLeg")
        add(k.caixa("bota", (0.17, 0.3, 0.12), (s * 0.11, -0.05, 0.07), BOTA, bevel=0.04), f"{lado}Foot")
        add(k.caixa("sola", (0.18, 0.31, 0.03), (s * 0.11, -0.05, 0.015), "preto"), f"{lado}Foot")

    return k.unir(p, ASSET_ID)


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
    """pose: osso -> [(eixo, graus), ...]; a chave especial "_quadril_z" desce/sobe o quadril (m)."""
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
        q = Quaternion()
        for eixo, graus in pose.get(pb.name, []):
            q = _rot(arm, pb.name, eixo, graus) @ q
        pb.rotation_quaternion = q
        pb.keyframe_insert("rotation_quaternion", frame=quadro)
    # o osso Hips aponta para +Z: o eixo Y local do osso é o "para cima" da armadura
    quadril = arm.pose.bones["Hips"]
    quadril.location = (0.0, pose.get("_quadril_z", 0.0), 0.0)
    quadril.keyframe_insert("location", frame=quadro)


X, Y, Z = (1, 0, 0), (0, 1, 0), (0, 0, 1)


def _pose_idle(t):
    """t em [0, 1): respiração e balanço leves, braços abaixados ao lado do corpo."""
    onda = math.sin(t * 2 * math.pi)
    return {
        "Chest": [(X, -1.5 * onda)],
        "Head": [(Z, 3 * onda), (X, 1.5 * onda)],
        "LeftUpperArm": [(Y, 72 - 2.5 * onda)],
        "RightUpperArm": [(Y, -72 + 2.5 * onda)],
        "LeftLowerArm": [(Z, -12)],
        "RightLowerArm": [(Z, 12)],
    }


def _ciclo(t, perna, joelho, braco, inclinacao, quadril_base=0.0, cotovelo=12, balanco_quadril=0.03):
    """Ciclo de passada. t em [0,1). Convenções (eixos da armadura, frente = -Y):
    ossos que apontam para baixo (pernas, braços abaixados) vão para a frente com X negativo;
    ossos que apontam para cima (tronco) inclinam para a frente com X positivo."""
    f = t * 2 * math.pi
    s_ = math.sin(f)
    # joelho dobra mais quando a perna está passando por trás
    joelho_e = joelho * (0.25 + 0.75 * max(0.0, math.sin(f + 1.2)))
    joelho_d = joelho * (0.25 + 0.75 * max(0.0, math.sin(f + 1.2 + math.pi)))
    return {
        "_quadril_z": quadril_base - balanco_quadril * abs(math.cos(f)),
        "Spine": [(Z, 4 * s_)],
        "Chest": [(X, inclinacao), (Z, -6 * s_)],
        "Head": [(X, -inclinacao * 0.6)],
        "LeftUpperLeg": [(X, -perna * s_)],
        "RightUpperLeg": [(X, perna * s_)],
        "LeftLowerLeg": [(X, joelho_e)],
        "RightLowerLeg": [(X, joelho_d)],
        "LeftUpperArm": [(Y, 72), (X, braco * s_)],
        "RightUpperArm": [(Y, -72), (X, -braco * s_)],
        "LeftLowerArm": [(Z, -cotovelo)],
        "RightLowerArm": [(Z, cotovelo)],
    }


def _agachado(t, passo=0.0):
    f = t * 2 * math.pi
    s_ = math.sin(f) * passo
    return {
        "_quadril_z": -0.42,
        "Chest": [(X, 18)],
        "Head": [(X, -14)],
        "LeftUpperLeg": [(X, -70 - s_)],
        "RightUpperLeg": [(X, -70 + s_)],
        "LeftLowerLeg": [(X, 110 + 0.5 * s_)],
        "RightLowerLeg": [(X, 110 - 0.5 * s_)],
        "LeftFoot": [(X, -40)],
        "RightFoot": [(X, -40)],
        "LeftUpperArm": [(Y, 65), (X, -25 + 0.6 * s_)],
        "RightUpperArm": [(Y, -65), (X, -25 - 0.6 * s_)],
        "LeftLowerArm": [(Z, -35)],
        "RightLowerArm": [(Z, 35)],
    }


def _no_ar(t):
    onda = math.sin(t * 2 * math.pi) * 4
    return {
        "Chest": [(X, -4)],
        "LeftUpperLeg": [(X, -38 + onda)],
        "LeftLowerLeg": [(X, 55)],
        "RightUpperLeg": [(X, -8 - onda)],
        "RightLowerLeg": [(X, 25)],
        "LeftUpperArm": [(Y, 40), (X, -15 + onda)],
        "RightUpperArm": [(Y, -40), (X, 10 - onda)],
        "LeftLowerArm": [(Z, -25)],
        "RightLowerArm": [(Z, 25)],
    }


# Pose de braços segurando uma arma com as duas mãos (sobrepõe os braços da locomoção).
BRACOS_ARMA = {
    "RightUpperArm": [(Z, 70), (X, 28)],
    "RightLowerArm": [(Z, 55), (X, -10)],
    "RightHand": [(X, -10)],
    "LeftUpperArm": [(Z, -55), (X, 22)],
    "LeftLowerArm": [(Z, -70), (X, -15)],
}


def _com_arma(pose_fn):
    def f(t):
        pose = dict(pose_fn(t))
        pose.update(BRACOS_ARMA)
        return pose
    return f


def _acao_ciclo(arm, nome, quadros, pose_fn, chaves=8):
    """Cria uma ação em loop: `chaves` amostras uniformes + a última igual à primeira."""
    acao = bpy.data.actions.new(nome)
    arm.animation_data.action = acao
    for i in range(chaves + 1):
        _chave(arm, 1 + round(i * quadros / chaves), pose_fn((i % chaves) / chaves))
    return acao


def animar(arm):
    arm.animation_data_create()
    acoes = []

    idle = bpy.data.actions.new("idle-loop")
    arm.animation_data.action = idle
    for i, q in enumerate(range(1, 62, 10)):
        _chave(arm, q, _pose_idle(i / 6.0))
    acoes.append(idle)

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

    # locomoção (30 fps): velocidades de referência no jogo — andar 4,5 m/s, correr 6,5 m/s, agachado 2,5 m/s
    acoes.append(_acao_ciclo(arm, "andar-loop", 30, lambda t: _ciclo(t, 28, 40, 22, 4)))
    acoes.append(_acao_ciclo(arm, "correr-loop", 20, lambda t: _ciclo(t, 45, 75, 40, 14, -0.04, 70, 0.06)))
    acoes.append(_acao_ciclo(arm, "agachado-loop", 60, lambda t: _agachado(t, 0.0), chaves=2))
    acoes.append(_acao_ciclo(arm, "agachado_andar-loop", 30, lambda t: _agachado(t, 22.0)))
    acoes.append(_acao_ciclo(arm, "no_ar-loop", 30, _no_ar, chaves=4))

    # variantes segurando arma (mesmas pernas/tronco, braços apontando a arma)
    acoes.append(_acao_ciclo(arm, "arma_idle-loop", 60, _com_arma(_pose_idle), chaves=6))
    acoes.append(_acao_ciclo(arm, "arma_andar-loop", 30, _com_arma(lambda t: _ciclo(t, 28, 40, 0, 4))))
    acoes.append(_acao_ciclo(arm, "arma_correr-loop", 20, _com_arma(lambda t: _ciclo(t, 45, 75, 0, 14, -0.04, 70, 0.06))))
    acoes.append(_acao_ciclo(arm, "arma_agachado-loop", 60, _com_arma(lambda t: _agachado(t, 0.0)), chaves=2))
    acoes.append(_acao_ciclo(arm, "arma_agachado_andar-loop", 30, _com_arma(lambda t: _agachado(t, 22.0))))
    acoes.append(_acao_ciclo(arm, "arma_no_ar-loop", 30, _com_arma(_no_ar), chaves=4))

    for a in acoes:
        a.use_fake_user = True
        trilha = arm.animation_data.nla_tracks.new()
        trilha.name = a.name
        trilha.strips.new(a.name, 1, a)
    arm.animation_data.action = None
    for pb in arm.pose.bones:
        pb.rotation_quaternion = Quaternion()
        pb.location = (0.0, 0.0, 0.0)


def recruta_base_01():
    malha = corpo()
    arm = esqueleto()
    malha.parent = arm
    mod = malha.modifiers.new("esqueleto", "ARMATURE")
    mod.object = arm
    malha["traje"] = "padrao"
    animar(arm)
    bpy.context.scene.frame_start, bpy.context.scene.frame_end = 1, 61


GERADORES = {ASSET_ID: recruta_base_01}


def main():
    for asset_id in sys.argv[1:] or list(GERADORES):
        k.nova_cena()
        GERADORES[asset_id]()
        k.salvar("personagens", asset_id)


if __name__ == "__main__":
    main()
