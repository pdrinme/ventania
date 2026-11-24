"""Animações do Ventania (revisão 1.4): autoria POSE A POSE, como um animador.

Cada ação é uma lista de poses-chave em tempo normalizado (0..1). Entre as chaves
a rotação de cada osso segue uma spline Catmull-Rom (movimento contínuo, sem
"parar" em cada pose) e cada osso tem um ATRASO próprio: o tronco puxa, e
pescoço, cabeça, antebraços e mãos chegam um pouco depois (sobreposição e
"arrasto", o que tira a cara de boneco). Ciclos de passada são escritos só para
a metade esquerda; a direita é o ESPELHO automático (troca Left/Right e inverte
os eixos laterais), então os dois lados ficam idênticos.

Convenções de eixo (as mesmas de gerar_personagem.py, verificadas em render):
  ossos para CIMA (Hips/Spine/Chest/Neck/Head): +X inclina para a frente,
    +Y inclina para a esquerda, +Z gira para a esquerda;
  pernas: -X leva a coxa para a frente; joelho +X dobra; pé -X levanta a ponta;
  braços em T: (Y, +a) abaixa o esquerdo, (Y, -a) o direito; depois (X, -f) leva
  para a frente; cotovelo esquerdo (Z, -a) e direito (Z, +a) dobram.
  "_quadril": deslocamento do quadril (lado, cima, frente) em metros.

As ações aditivas (reacao_*) só mexem no tronco e na cabeça: na Godot elas são
somadas por cima de qualquer locomoção (OneShot em modo ADD, com filtro), e as
mãos continuam presas à arma pelo IK, então o recuo e a recarga movem a arma.
"""

import math

import bpy
from mathutils import Quaternion, Vector

X, Y, Z = (1, 0, 0), (0, 1, 0), (0, 0, 1)

# atraso de cada osso (fração do ciclo): a ponta da cadeia chega depois
ATRASO = {"Hips": 0.0, "Spine": 0.01, "Chest": 0.02, "Neck": 0.04, "Head": 0.06,
          "LeftShoulder": 0.02, "RightShoulder": 0.02, "LeftUpperArm": 0.03, "RightUpperArm": 0.03,
          "LeftLowerArm": 0.06, "RightLowerArm": 0.06, "LeftHand": 0.09, "RightHand": 0.09}
SEM_ATRASO = {}


# ---------------------------------------------------------------- utilidades de pose
def espelho(pose):
    """Pose do lado oposto: troca Left/Right e inverte as componentes laterais (Y, Z)."""
    out = {}
    for osso, rots in pose.items():
        if osso == "_quadril":
            l, c, f = rots
            out[osso] = (-l, c, f)
            continue
        alvo = osso.replace("Left", "@").replace("Right", "Left").replace("@", "Right")
        out[alvo] = [(e, g if e == X else -g) for e, g in rots]
    return out


def junta(*poses):
    """Soma de poses (as rotações de um osso são compostas em ordem)."""
    out = {}
    for p in poses:
        for osso, v in p.items():
            if osso == "_quadril":
                a = out.get(osso, (0.0, 0.0, 0.0))
                out[osso] = tuple(a[i] + v[i] for i in range(3))
            else:
                out[osso] = list(out.get(osso, [])) + list(v)
    return out


def bracos(esq_frente, dir_frente, cot_e, cot_d, abaixar=74.0, abrir_e=0.0, abrir_d=0.0, punho_e=-8, punho_d=8):
    """Braços ao lado do corpo, balançando para a frente/trás (graus)."""
    return {
        "LeftShoulder": [(Y, 4)], "RightShoulder": [(Y, -4)],
        "LeftUpperArm": [(Y, abaixar - abrir_e), (X, -esq_frente)],
        "RightUpperArm": [(Y, -abaixar + abrir_d), (X, -dir_frente)],
        "LeftLowerArm": [(Z, -cot_e)], "RightLowerArm": [(Z, cot_d)],
        "LeftHand": [(Z, punho_e)], "RightHand": [(Z, punho_d)],
    }


def _rot(arm, osso, eixo, graus):
    m = arm.data.bones[osso].matrix_local.to_3x3()
    r = Quaternion(Vector(eixo), math.radians(graus)).to_matrix()
    return (m.inverted() @ r @ m).to_quaternion()


def _quats(arm, pose):
    q = {}
    for pb in arm.pose.bones:
        acc = Quaternion()
        for eixo, g in pose.get(pb.name, []):
            acc = _rot(arm, pb.name, eixo, g) @ acc
        q[pb.name] = acc
    return q, Vector(pose.get("_quadril", (0.0, 0.0, 0.0)))


def _catmull(p0, p1, p2, p3, t):
    t2, t3 = t * t, t * t * t
    return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)


def _q_catmull(q0, q1, q2, q3, t):
    # alinha os hemisférios (q e -q são a mesma rotação) e interpola por componente
    a = [q0, q1, q2, q3]
    for i in range(1, 4):
        if a[i - 1].dot(a[i]) < 0:
            a[i] = -a[i]
    v = [Vector((q.w, q.x, q.y, q.z)) for q in a]
    r = _catmull(v[0], v[1], v[2], v[3], t)
    q = Quaternion((r[0], r[1], r[2], r[3]))
    q.normalize()
    return q


# ---------------------------------------------------------------- criação da ação
def acao(arm, nome, quadros, chaves, loop=True, atrasos=ATRASO, suave_extremos=True):
    """chaves: [(t 0..1, pose)], em ordem. Em loop, a primeira chave repete em t=1.
    Amostra quadro a quadro (30 fps) com spline e atraso por osso."""
    ts = [t for t, _ in chaves]
    dados = [_quats(arm, p) for _, p in chaves]
    n = len(chaves)

    def indice(i):
        if loop:
            return i % n
        return max(0, min(n - 1, i))

    def tempo(i):
        if loop:
            return ts[i % n] + (i // n) * 1.0
        return ts[max(0, min(n - 1, i))]

    def amostra(t):
        """(quats por osso, quadril) no tempo t, cada osso com o seu atraso."""
        out_q = {}
        quadril = None
        for osso in [pb.name for pb in arm.pose.bones] + ["_quadril"]:
            tb = t - atrasos.get(osso if osso != "_quadril" else "Hips", 0.0)
            if loop:
                tb %= 1.0
            else:
                tb = max(ts[0], min(ts[-1], tb))
            # segmento [i, i+1] que contém tb
            i = 0
            while i + 1 < (n + (1 if loop else 0)) and tempo(i + 1) <= tb:
                i += 1
            if not loop and i >= n - 1:
                i = n - 2
            t0, t1 = tempo(i), tempo(i + 1)
            u = 0.0 if t1 <= t0 else (tb - t0) / (t1 - t0)
            u = max(0.0, min(1.0, u))
            ids = [indice(i - 1), indice(i), indice(i + 1), indice(i + 2)]
            if not loop and suave_extremos:
                ids[0] = indice(i - 1) if i > 0 else ids[1]
                ids[3] = indice(i + 2) if i + 2 < n else ids[2]
            if osso == "_quadril":
                quadril = _catmull(*[dados[k][1] for k in ids], u)
            else:
                out_q[osso] = _q_catmull(*[dados[k][0][osso] for k in ids], u)
        return out_q, quadril

    a = bpy.data.actions.new(nome)
    arm.animation_data.action = a
    for f in range(quadros + 1):
        t = f / quadros
        if loop and f == quadros:
            t = 0.0
        q, quadril = amostra(t)
        for pb in arm.pose.bones:
            pb.rotation_mode = "QUATERNION"
            pb.rotation_quaternion = q[pb.name]
            pb.keyframe_insert("rotation_quaternion", frame=1 + f)
        hb = arm.pose.bones["Hips"]
        # Hips aponta para +Z: no espaço local do osso, X = lado, Y = cima, Z = -frente
        hb.location = (quadril.x, quadril.y, -quadril.z)
        hb.keyframe_insert("location", frame=1 + f)
    return a


# ---------------------------------------------------------------- IDLE
def idle():
    """4 s: peso na perna direita (contrapposto), respiração, troca de peso no meio,
    uma olhada para o lado e um ajuste de ombros — viva, mas calma."""
    base = junta({
        "_quadril": (-0.022, -0.014, 0.0),
        "Hips": [(Y, 3.0), (Z, 4.0)],
        "Spine": [(X, 1.5), (Y, -1.5), (Z, -3.0)],
        "Chest": [(Y, -1.5), (Z, -2.0)],
        "Neck": [(X, 1.0)], "Head": [(X, 2.0), (Y, 3.0), (Z, -4.0)],
        "LeftUpperLeg": [(Y, -3.0), (X, -6), (Z, 6)], "RightUpperLeg": [(Y, -2.0), (X, -1)],
        "LeftLowerLeg": [(X, 12)], "RightLowerLeg": [(X, 3)],
        "LeftFoot": [(X, -4)], "RightFoot": [(X, -2)],
    }, bracos(5, 3, 16, 12, abaixar=76))
    inspira = {"Spine": [(X, -1.2)], "Chest": [(X, -2.0)], "LeftShoulder": [(Y, -1.5)], "RightShoulder": [(Y, 1.5)],
               "_quadril": (0.0, 0.004, 0.0)}
    olha = {"Head": [(Z, 22), (X, -3)], "Neck": [(Z, 8)], "Chest": [(Z, 3)]}
    troca = {"_quadril": (0.03, 0.0, 0.0), "Hips": [(Y, -4.5)], "LeftLowerLeg": [(X, -7)], "RightLowerLeg": [(X, 6)]}
    ombros = {"LeftShoulder": [(Y, -5)], "RightShoulder": [(Y, 5)], "Head": [(Y, -4)]}
    return [(0.0, base), (0.14, junta(base, inspira)), (0.28, base),
            (0.4, junta(base, olha)), (0.52, junta(base, olha, inspira)), (0.62, base),
            (0.74, junta(base, troca)), (0.84, junta(base, troca, ombros, inspira)), (0.93, junta(base, troca))]


# ---------------------------------------------------------------- PASSADAS
def _passada(contato, desce, passa, sobe):
    """Metade esquerda (perna esquerda à frente no contato) + espelho."""
    return [(0.0, contato), (0.125, desce), (0.25, passa), (0.375, sobe),
            (0.5, espelho(contato)), (0.625, espelho(desce)), (0.75, espelho(passa)), (0.875, espelho(sobe))]


def caminhar():
    """Caminhada lenta (~1,8 m/s, 1,1 s por ciclo): calcanhar, rola, empurra com a
    ponta; quadril sobe na passagem; braços soltos e contrários às pernas."""
    tronco = {"Spine": [(X, 2)], "Chest": [(X, 1)], "Neck": [(X, -1)], "Head": [(X, -1)]}
    contato = junta(tronco, {
        "_quadril": (0.012, -0.03, 0.0), "Hips": [(Z, -5), (Y, 1)], "Chest": [(Z, 5)], "Head": [(Z, -1.5)],
        "LeftUpperLeg": [(X, -24)], "LeftLowerLeg": [(X, 4)], "LeftFoot": [(X, -14)],
        "RightUpperLeg": [(X, 18)], "RightLowerLeg": [(X, 14)], "RightFoot": [(X, 20)],
    }, bracos(-16, 18, 10, 22))
    desce = junta(tronco, {
        "_quadril": (0.018, -0.045, 0.0), "Hips": [(Z, -3), (Y, 3)], "Chest": [(Z, 3)],
        "LeftUpperLeg": [(X, -16)], "LeftLowerLeg": [(X, 18)], "LeftFoot": [(X, 2)],
        "RightUpperLeg": [(X, 14)], "RightLowerLeg": [(X, 34)], "RightFoot": [(X, 22)],
    }, bracos(-10, 12, 10, 18))
    passa = junta(tronco, {
        "_quadril": (0.02, -0.008, 0.0), "Hips": [(Y, 2)],
        "LeftUpperLeg": [(X, 0)], "LeftLowerLeg": [(X, 8)], "LeftFoot": [(X, 0)],
        "RightUpperLeg": [(X, -8)], "RightLowerLeg": [(X, 52)], "RightFoot": [(X, -6)],
    }, bracos(0, 0, 12, 14))
    sobe = junta(tronco, {
        "_quadril": (0.014, 0.004, 0.0), "Hips": [(Z, 3)], "Chest": [(Z, -3)],
        "LeftUpperLeg": [(X, 14)], "LeftLowerLeg": [(X, 6)], "LeftFoot": [(X, 10)],
        "RightUpperLeg": [(X, -22)], "RightLowerLeg": [(X, 22)], "RightFoot": [(X, -12)],
    }, bracos(12, -10, 18, 10))
    return _passada(contato, desce, passa, sobe)


def corrida():
    """Corrida (4,5 m/s, 0,72 s por ciclo): tronco inclinado, braços dobrados a 80°
    balançando firme, joelho alto na passagem e uma fase de voo curta."""
    tronco = {"Spine": [(X, 6)], "Chest": [(X, 4)], "Neck": [(X, -4)], "Head": [(X, -5)]}
    contato = junta(tronco, {
        "_quadril": (0.01, -0.04, 0.0), "Hips": [(Z, -7)], "Chest": [(Z, 8)], "Head": [(Z, -2)],
        "LeftUpperLeg": [(X, -32)], "LeftLowerLeg": [(X, 14)], "LeftFoot": [(X, -10)],
        "RightUpperLeg": [(X, 26)], "RightLowerLeg": [(X, 40)], "RightFoot": [(X, 26)],
    }, bracos(-32, 36, 78, 92, abaixar=70))
    desce = junta(tronco, {
        "_quadril": (0.016, -0.075, 0.0), "Hips": [(Z, -4), (Y, 2)], "Chest": [(Z, 5), (X, 2)],
        "LeftUpperLeg": [(X, -18)], "LeftLowerLeg": [(X, 36)], "LeftFoot": [(X, 6)],
        "RightUpperLeg": [(X, 18)], "RightLowerLeg": [(X, 72)], "RightFoot": [(X, 22)],
    }, bracos(-22, 26, 82, 90, abaixar=70))
    passa = junta(tronco, {
        "_quadril": (0.016, -0.03, 0.0),
        "LeftUpperLeg": [(X, 4)], "LeftLowerLeg": [(X, 24)], "LeftFoot": [(X, 12)],
        "RightUpperLeg": [(X, -26)], "RightLowerLeg": [(X, 100)], "RightFoot": [(X, -6)],
    }, bracos(0, 4, 86, 86, abaixar=70))
    voo = junta(tronco, {
        "_quadril": (0.01, 0.01, 0.0), "Hips": [(Z, 6)], "Chest": [(Z, -7)],
        "LeftUpperLeg": [(X, 24)], "LeftLowerLeg": [(X, 26)], "LeftFoot": [(X, 32)],
        "RightUpperLeg": [(X, -40)], "RightLowerLeg": [(X, 50)], "RightFoot": [(X, -12)],
    }, bracos(30, -28, 92, 76, abaixar=70))
    return _passada(contato, desce, passa, voo)


def sprint():
    """Sprint (6,5 m/s, 0,6 s por ciclo): bem inclinado, passadas longas, joelho
    muito alto, braços "socando" o ar, cabeça firme olhando à frente."""
    tronco = {"Hips": [(X, 8)], "Spine": [(X, 14)], "Chest": [(X, 10)], "Neck": [(X, -12)], "Head": [(X, -16)]}
    contato = junta(tronco, {
        "_quadril": (0.008, -0.05, 0.03), "Hips": [(Z, -9)], "Chest": [(Z, 11)], "Head": [(Z, -3)],
        "LeftUpperLeg": [(X, -44)], "LeftLowerLeg": [(X, 22)], "LeftFoot": [(X, -8)],
        "RightUpperLeg": [(X, 30)], "RightLowerLeg": [(X, 56)], "RightFoot": [(X, 32)],
    }, bracos(-48, 52, 84, 100, abaixar=66))
    desce = junta(tronco, {
        "_quadril": (0.012, -0.085, 0.03), "Hips": [(Z, -5)], "Chest": [(Z, 6), (X, 3)],
        "LeftUpperLeg": [(X, -26)], "LeftLowerLeg": [(X, 40)], "LeftFoot": [(X, 8)],
        "RightUpperLeg": [(X, 22)], "RightLowerLeg": [(X, 96)], "RightFoot": [(X, 24)],
    }, bracos(-30, 34, 90, 96, abaixar=66))
    passa = junta(tronco, {
        "_quadril": (0.012, -0.035, 0.03),
        "LeftUpperLeg": [(X, 6)], "LeftLowerLeg": [(X, 30)], "LeftFoot": [(X, 16)],
        "RightUpperLeg": [(X, -40)], "RightLowerLeg": [(X, 122)], "RightFoot": [(X, -4)],
    }, bracos(2, 6, 92, 92, abaixar=66))
    voo = junta(tronco, {
        "_quadril": (0.008, 0.02, 0.03), "Hips": [(Z, 8)], "Chest": [(Z, -10)],
        "LeftUpperLeg": [(X, 34)], "LeftLowerLeg": [(X, 34)], "LeftFoot": [(X, 40)],
        "RightUpperLeg": [(X, -58)], "RightLowerLeg": [(X, 64)], "RightFoot": [(X, -14)],
    }, bracos(46, -44, 100, 82, abaixar=66))
    return _passada(contato, desce, passa, voo)


# ---------------------------------------------------------------- AGACHADO
def _agachado_base():
    return junta({
        "_quadril": (0.0, -0.42, 0.05),
        "Hips": [(X, 10)], "Spine": [(X, 12)], "Chest": [(X, 8)], "Neck": [(X, -10)], "Head": [(X, -12)],
        "LeftUpperLeg": [(X, -74), (Y, -4)], "RightUpperLeg": [(X, -66), (Y, 4)],
        "LeftLowerLeg": [(X, 112)], "RightLowerLeg": [(X, 104)],
        "LeftFoot": [(X, -34)], "RightFoot": [(X, -30)],
    }, bracos(20, 16, 44, 40, abaixar=66))


def agachado():
    """2 s: agachado atento, respirando, balança o peso e olha em volta."""
    b = _agachado_base()
    return [(0.0, b), (0.25, junta(b, {"_quadril": (0.012, 0.01, 0.0), "Chest": [(X, -2)], "Head": [(Z, 14)]})),
            (0.5, junta(b, {"_quadril": (0.0, -0.006, 0.0)})),
            (0.75, junta(b, {"_quadril": (-0.012, 0.01, 0.0), "Chest": [(X, -2)], "Head": [(Z, -12)]}))]


def agachado_andar():
    """Andar agachado (2,5 m/s, 1,0 s por ciclo): passos de gato, quadril baixo."""
    b = _agachado_base()
    contato = junta(b, {"_quadril": (0.01, -0.01, 0.0), "Hips": [(Z, -5)], "Chest": [(Z, 5)],
                        "LeftUpperLeg": [(X, -18)], "LeftLowerLeg": [(X, -12)], "RightUpperLeg": [(X, 16)], "RightLowerLeg": [(X, 6)]},
                    {"LeftUpperArm": [(X, 8)], "RightUpperArm": [(X, -8)]})
    desce = junta(b, {"_quadril": (0.014, -0.03, 0.0), "LeftUpperLeg": [(X, -8)], "RightUpperLeg": [(X, 10)], "RightLowerLeg": [(X, 10)]})
    passa = junta(b, {"_quadril": (0.014, 0.0, 0.0), "RightUpperLeg": [(X, -12)], "RightLowerLeg": [(X, 18)], "RightFoot": [(X, -6)]})
    sobe = junta(b, {"_quadril": (0.01, 0.005, 0.0), "Hips": [(Z, 4)], "Chest": [(Z, -4)],
                     "LeftUpperLeg": [(X, 12)], "RightUpperLeg": [(X, -20)], "RightLowerLeg": [(X, 4)]},
                 {"LeftUpperArm": [(X, -8)], "RightUpperArm": [(X, 8)]})
    return _passada(contato, desce, passa, sobe)


# ---------------------------------------------------------------- PULO, QUEDA, ATERRISSAGEM
def pular():
    """0,5 s: empurra com as pernas (extensão), braços sobem; encolhe no ápice."""
    impulso = junta({
        "_quadril": (0.0, 0.02, 0.0), "Spine": [(X, -6)], "Chest": [(X, -8)], "Head": [(X, 6)],
        "LeftUpperLeg": [(X, 10)], "RightUpperLeg": [(X, 4)], "LeftLowerLeg": [(X, 4)], "RightLowerLeg": [(X, 8)],
        "LeftFoot": [(X, 34)], "RightFoot": [(X, 30)],
    }, bracos(-50, -42, 30, 34, abaixar=48))
    sobe = junta({
        "_quadril": (0.0, 0.03, 0.0), "Spine": [(X, 2)], "Chest": [(X, 2)], "Head": [(X, 2)],
        "LeftUpperLeg": [(X, -46)], "RightUpperLeg": [(X, -18)], "LeftLowerLeg": [(X, 74)], "RightLowerLeg": [(X, 42)],
        "LeftFoot": [(X, 10)], "RightFoot": [(X, 16)],
    }, bracos(-30, -20, 40, 46, abaixar=38, abrir_e=6, abrir_d=6))
    apice = junta({
        "Spine": [(X, 6)], "Chest": [(X, 4)], "Head": [(X, -2)],
        "LeftUpperLeg": [(X, -40)], "RightUpperLeg": [(X, -24)], "LeftLowerLeg": [(X, 62)], "RightLowerLeg": [(X, 48)],
        "LeftFoot": [(X, 6)], "RightFoot": [(X, 10)],
    }, bracos(-8, 0, 36, 40, abaixar=36, abrir_e=10, abrir_d=10))
    return [(0.0, impulso), (0.35, sobe), (1.0, apice)]


def queda():
    """0,8 s em loop: braços abertos e soltos "nadando" no ar, pernas pedalando
    devagar, olhando para baixo (procura o chão)."""
    def p(fase):
        s = math.sin(fase)
        return junta({
            "Spine": [(X, 4)], "Chest": [(X, -2 + 2 * s)], "Neck": [(X, 4)], "Head": [(X, 8)],
            "LeftUpperLeg": [(X, -30 + 10 * s)], "RightUpperLeg": [(X, -12 - 10 * s)],
            "LeftLowerLeg": [(X, 50 - 8 * s)], "RightLowerLeg": [(X, 32 + 8 * s)],
            "LeftFoot": [(X, 12)], "RightFoot": [(X, 14)],
        }, bracos(10 + 6 * s, 4 - 6 * s, 30 + 8 * s, 30 - 8 * s, abaixar=34 + 6 * s, abrir_e=0, abrir_d=0))
    return [(i / 4, p(i / 4 * math.tau)) for i in range(4)]


def aterrissar():
    """0,55 s: toca com as pontas, AMORTECE fundo (joelhos, tronco à frente,
    braços à frente para equilibrar), passa um pouco ao subir e assenta."""
    em_pe = bracos(4, 4, 14, 14, abaixar=76)
    toque = junta({"_quadril": (0.0, -0.04, 0.0), "LeftUpperLeg": [(X, -20)], "RightUpperLeg": [(X, -14)],
                   "LeftLowerLeg": [(X, 24)], "RightLowerLeg": [(X, 20)], "LeftFoot": [(X, 10)], "RightFoot": [(X, 10)]},
                  bracos(-6, -6, 30, 30, abaixar=50))
    fundo = junta({"_quadril": (0.0, -0.3, 0.03), "Hips": [(X, 12)], "Spine": [(X, 14)], "Chest": [(X, 12)],
                   "Neck": [(X, -10)], "Head": [(X, -14)],
                   "LeftUpperLeg": [(X, -56)], "RightUpperLeg": [(X, -48)], "LeftLowerLeg": [(X, 96)], "RightLowerLeg": [(X, 88)],
                   "LeftFoot": [(X, -38)], "RightFoot": [(X, -36)]},
                  bracos(28, 32, 40, 44, abaixar=58, abrir_e=8, abrir_d=8))
    sobe = junta({"_quadril": (0.0, -0.06, 0.0), "Spine": [(X, -2)], "Chest": [(X, -3)], "Head": [(X, 3)],
                  "LeftUpperLeg": [(X, -10)], "RightUpperLeg": [(X, -8)], "LeftLowerLeg": [(X, 18)], "RightLowerLeg": [(X, 16)],
                  "LeftFoot": [(X, -6)], "RightFoot": [(X, -6)]}, bracos(0, 0, 18, 18, abaixar=72))
    assenta = junta({"_quadril": (0.0, -0.012, 0.0), "LeftLowerLeg": [(X, 5)], "RightLowerLeg": [(X, 4)]}, em_pe)
    return [(0.0, toque), (0.22, fundo), (0.62, sobe), (1.0, assenta)]


# ---------------------------------------------------------------- ELIMINAÇÃO
def eliminado():
    """1,6 s: o golpe joga o tronco para trás, o corpo gira, cai de joelhos e tomba
    de lado no chão (depois, na Godot, o vento leva o corpo embora)."""
    em_pe = bracos(4, 4, 14, 14, abaixar=76)
    golpe = junta({"_quadril": (0.0, 0.0, -0.06), "Spine": [(X, -16)], "Chest": [(X, -18), (Z, 12)], "Neck": [(X, -10)], "Head": [(X, -22), (Z, 14)],
                   "LeftUpperLeg": [(X, -12)], "RightUpperLeg": [(X, 8)], "LeftLowerLeg": [(X, 14)], "RightLowerLeg": [(X, 8)]},
                  bracos(-40, -10, 30, 60, abaixar=40, abrir_e=20, abrir_d=10))
    cambaleia = junta({"_quadril": (-0.04, -0.08, -0.08), "Hips": [(Z, 20)], "Spine": [(X, 6), (Y, -8)], "Chest": [(X, 12), (Z, 16)],
                       "Head": [(X, 18), (Z, 10)],
                       "LeftUpperLeg": [(X, -20)], "RightUpperLeg": [(X, 22)], "LeftLowerLeg": [(X, 40)], "RightLowerLeg": [(X, 24)]},
                      bracos(10, 20, 40, 30, abaixar=62))
    joelhos = junta({"_quadril": (-0.05, -0.5, -0.02), "Hips": [(Z, 28), (X, 6)], "Spine": [(X, 18), (Y, -10)], "Chest": [(X, 14), (Z, 8)],
                     "Head": [(X, 24), (Y, -10)],
                     "LeftUpperLeg": [(X, -8)], "RightUpperLeg": [(X, 4)], "LeftLowerLeg": [(X, 100)], "RightLowerLeg": [(X, 96)],
                     "LeftFoot": [(X, 30)], "RightFoot": [(X, 30)]},
                    bracos(20, 30, 20, 20, abaixar=72))
    tomba = junta({"_quadril": (-0.25, -0.78, 0.1), "Hips": [(Z, 30), (Y, 78)], "Spine": [(X, 6), (Y, 8)], "Chest": [(X, 4)],
                   "Neck": [(Y, 10)], "Head": [(Y, 14), (X, 6)],
                   "LeftUpperLeg": [(X, -30)], "RightUpperLeg": [(X, -10)], "LeftLowerLeg": [(X, 60)], "RightLowerLeg": [(X, 30)],
                   "LeftFoot": [(X, 10)], "RightFoot": [(X, 10)]},
                  bracos(-30, 40, 30, 20, abaixar=40, abrir_e=0, abrir_d=30))
    deitado = junta(tomba, {"_quadril": (-0.02, -0.04, 0.0), "Head": [(Y, 4)], "LeftLowerArm": [(Z, 10)]})
    return [(0.0, em_pe), (0.08, golpe), (0.3, cambaleia), (0.52, joelhos), (0.78, tomba), (1.0, deitado)]


# ---------------------------------------------------------------- REAÇÕES (aditivas)
def reacao_tiro():
    """0,25 s: o tronco recebe o coice e volta (ombros, peito, cabeça)."""
    zero = {}
    coice = {"Spine": [(X, -2.5)], "Chest": [(X, -5), (Z, -2)], "Neck": [(X, 2)], "Head": [(X, 3)],
             "RightShoulder": [(Y, 3)]}
    volta = {"Spine": [(X, 0.6)], "Chest": [(X, 1.2)]}
    return [(0.0, zero), (0.18, coice), (0.6, volta), (1.0, zero)]


def reacao_recarga():
    """1,0 s: inclina e gira o tronco para a arma, cabeça olha o carregador,
    pequena "batida" ao encaixar e volta à mira."""
    zero = {}
    olha = {"Spine": [(X, 5), (Z, -6)], "Chest": [(X, 6), (Z, -8)], "Neck": [(X, 8)], "Head": [(X, 14), (Z, -8)]}
    encaixe = {"Spine": [(X, 3), (Z, -4)], "Chest": [(X, 9), (Z, -6)], "Neck": [(X, 6)], "Head": [(X, 10), (Z, -4)]}
    return [(0.0, zero), (0.22, olha), (0.62, olha), (0.72, encaixe), (0.86, olha), (1.0, zero)]


def reacao_equipar():
    """0,35 s: o tronco gira um pouco para o lado do saque e volta."""
    zero = {}
    gira = {"Spine": [(Z, -5)], "Chest": [(Z, -9), (X, 3)], "Head": [(Z, 5)]}
    return [(0.0, zero), (0.4, gira), (1.0, zero)]


# ---------------------------------------------------------------- lista
def criar_todas(arm):
    """Cria as ações da revisão 1.4 e devolve a lista (para as trilhas NLA)."""
    return [
        acao(arm, "idle-loop", 120, idle()),
        acao(arm, "caminhar-loop", 34, caminhar()),
        acao(arm, "andar-loop", 22, corrida()),          # corrida normal (velocidade padrão)
        acao(arm, "correr-loop", 18, sprint()),          # sprint
        acao(arm, "agachado-loop", 60, agachado()),
        acao(arm, "agachado_andar-loop", 30, agachado_andar()),
        acao(arm, "pular", 15, pular(), loop=False),
        acao(arm, "queda-loop", 24, queda()),
        acao(arm, "aterrissar", 16, aterrissar(), loop=False),
        acao(arm, "eliminado", 48, eliminado(), loop=False),
        acao(arm, "reacao_tiro", 8, reacao_tiro(), loop=False, atrasos=SEM_ATRASO),
        acao(arm, "reacao_recarga", 30, reacao_recarga(), loop=False),
        acao(arm, "reacao_equipar", 10, reacao_equipar(), loop=False, atrasos=SEM_ATRASO),
    ]
