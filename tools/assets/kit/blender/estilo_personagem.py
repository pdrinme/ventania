"""Biblioteca de modelagem dos personagens do Ventania (revisão de arte).

Substitui o "boneco de primitivas" por personagens modelados:
  - CORPO contínuo e orgânico: grafo de juntas com o modificador Skin (raios
    elípticos por junta: ombros, cintura, quadril, panturrilha...) + subdivisão,
    com PESOS SUAVES calculados das distâncias aos ossos (dobra de cotovelo,
    joelho e ombro sem quebrar);
  - ROUPAS em camadas: cascas do próprio corpo (deslocadas pela normal) por
    região, com punhos, barras, golas, cós, bolsos, costuras e zíper; os pesos
    são copiados do corpo (deformam junto);
  - CABEÇA esculpida (mandíbula, queixo, bochechas, nuca) com OLHOS de verdade
    (branco, íris, pupila, brilho, pálpebra e cílio), sobrancelhas, nariz, boca,
    orelhas e CABELO em mechas;
  - MÃOS com luva e dedos, CALÇADOS esculpidos (sola, biqueira, cano, cadarço).
Esqueleto, nomes de ossos e animações: os mesmos de gerar_personagem.py.

Coordenadas Blender: Z para cima, frente = -Y, esquerda = +X (T-pose).
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bmesh  # noqa: E402
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

import kit_comum as k  # noqa: E402

# ---------------------------------------------------------------- proporções
# Medidas por tipo de corpo: (raio x, raio y) por junta. Altura fixa (esqueleto).
CORPOS = {
    "padrao": {"ombro": 0.205, "peito": (0.19, 0.125), "cintura": (0.15, 0.11), "quadril": (0.165, 0.12),
               "braco": 0.066, "cotovelo": 0.054, "pulso": 0.046, "coxa": 0.09, "joelho": 0.064, "tornozelo": 0.048,
               "pescoco": 0.052},
    "fino": {"ombro": 0.19, "peito": (0.175, 0.118), "cintura": (0.128, 0.098), "quadril": (0.168, 0.12),
             "braco": 0.058, "cotovelo": 0.047, "pulso": 0.04, "coxa": 0.086, "joelho": 0.058, "tornozelo": 0.043,
             "pescoco": 0.047},
    "robusto": {"ombro": 0.225, "peito": (0.215, 0.145), "cintura": (0.18, 0.135), "quadril": (0.18, 0.13),
                "braco": 0.076, "cotovelo": 0.062, "pulso": 0.052, "coxa": 0.1, "joelho": 0.075, "tornozelo": 0.056,
                "pescoco": 0.06},
}

# Ossos (cabeça, cauda) — mesmos de gerar_personagem.OSSOS
def _ossos():
    import gerar_personagem as gp
    return {n: (Vector(c), Vector(t)) for n, c, t, _ in gp.OSSOS}


def _dist_segmento(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(1e-9, ab.dot(ab))))
    return (p - (a + ab * t)).length


# Ossos que deformam a pele e o "alcance" de cada um (suavidade da mistura)
OSSOS_PELE = ["Hips", "Spine", "Chest", "Neck", "Head",
              "LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand",
              "RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand",
              "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot"]
# pares que podem se misturar (vizinhos na cadeia): evita, p.ex., coxa puxando a mão
VIZINHOS = {
    "Hips": {"Spine", "LeftUpperLeg", "RightUpperLeg"}, "Spine": {"Hips", "Chest"},
    "Chest": {"Spine", "Neck", "LeftShoulder", "RightShoulder", "LeftUpperArm", "RightUpperArm"},
    "Neck": {"Chest", "Head"}, "Head": {"Neck"},
}
for _l in ("Left", "Right"):
    VIZINHOS[f"{_l}Shoulder"] = {"Chest", f"{_l}UpperArm"}
    VIZINHOS[f"{_l}UpperArm"] = {f"{_l}Shoulder", f"{_l}LowerArm", "Chest"}
    VIZINHOS[f"{_l}LowerArm"] = {f"{_l}UpperArm", f"{_l}Hand"}
    VIZINHOS[f"{_l}Hand"] = {f"{_l}LowerArm"}
    VIZINHOS[f"{_l}UpperLeg"] = {"Hips", f"{_l}LowerLeg"}
    VIZINHOS[f"{_l}LowerLeg"] = {f"{_l}UpperLeg", f"{_l}Foot"}
    VIZINHOS[f"{_l}Foot"] = {f"{_l}LowerLeg"}


def pesos_suaves(obj, nitidez=6.0):
    """Pesos de deformação pela distância aos ossos (inverso da distância elevado a
    `nitidez`), só entre ossos vizinhos na cadeia e no máximo 3 por vértice. Mais
    previsível que o 'heat' do Blender para malhas geradas, e sem buracos."""
    ossos = _ossos()
    for g in list(obj.vertex_groups):
        obj.vertex_groups.remove(g)
    grupos = {n: obj.vertex_groups.new(name=n) for n in OSSOS_PELE}
    mw = obj.matrix_world
    for v in obj.data.vertices:
        p = mw @ v.co
        d = {n: _dist_segmento(p, *ossos[n]) for n in OSSOS_PELE}
        # o osso mais perto manda; mistura só com os vizinhos dele
        dono = min(d, key=d.get)
        candidatos = [dono] + [n for n in VIZINHOS[dono] if n in d]
        # lados não se misturam (perna esquerda nunca puxa a direita)
        if p.x > 0.06:
            candidatos = [n for n in candidatos if not n.startswith("Right")]
        elif p.x < -0.06:
            candidatos = [n for n in candidatos if not n.startswith("Left")]
        w = {n: 1.0 / max(1e-4, d[n]) ** nitidez for n in candidatos}
        top = sorted(w.items(), key=lambda kv: -kv[1])[:3]
        soma = sum(x for _, x in top)
        for n, x in top:
            if x / soma > 0.02:
                grupos[n].add([v.index], x / soma, "REPLACE")
    return obj


def osso_mais_perto(pos):
    """Osso cujo segmento passa mais perto de um ponto (para presilhas, punhos, bolsos)."""
    ossos = _ossos()
    p = Vector(pos)
    return min(OSSOS_PELE, key=lambda n: _dist_segmento(p, *ossos[n]))


def centro(o):
    """Centro do objeto (média dos vértices, em coordenadas do mundo)."""
    vs = o.data.vertices
    if not vs:
        return o.matrix_world.translation
    soma = Vector()
    for v in vs:
        soma += o.matrix_world @ v.co
    return soma / len(vs)


def rigido(obj, osso):
    """Peça rígida (peso 1 num osso): acessórios, cabeça, mãos, calçados."""
    for g in list(obj.vertex_groups):
        obj.vertex_groups.remove(g)
    g = obj.vertex_groups.new(name=osso)
    g.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
    return obj


def mundo(o):
    """Grava a posição do objeto nos vértices (coordenadas de mundo), para cortes e
    deformações por altura/posição funcionarem com números do mundo."""
    k._ativo(o)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return o


def _novo_obj(nome, bm):
    malha = bpy.data.meshes.new(nome)
    bm.to_mesh(malha)
    bm.free()
    o = bpy.data.objects.new(nome, malha)
    bpy.context.scene.collection.objects.link(o)
    return o


def _aplicar_mods(o):
    k._ativo(o)
    for m in list(o.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)


def _suave(o, ang=60):
    k._suavizar(o, ang)
    return o


# ---------------------------------------------------------------- corpo
def corpo_base(tipo="padrao", cor="pele_2", sem_bracos=False):
    """Corpo inteiro numa malha só (pescoço até os tornozelos e pulsos)."""
    c = CORPOS[tipo]
    juntas = []      # (pos, (rx, ry))
    arestas = []

    def j(p, r):
        juntas.append((Vector(p), r if isinstance(r, tuple) else (r, r)))
        return len(juntas) - 1

    quad = j((0, 0, 0.94), c["quadril"])                          # 0: raiz
    cint = j((0, 0.005, 1.08), c["cintura"])
    peito = j((0, -0.01, 1.25), c["peito"])
    topo = j((0, 0.0, 1.37), (c["peito"][0] * 0.82, c["peito"][1] * 0.85))
    pesc0 = j((0, 0.005, 1.45), c["pescoco"])
    pesc1 = j((0, 0.01, 1.53), c["pescoco"] * 0.95)
    arestas += [(quad, cint), (cint, peito), (peito, topo), (topo, pesc0), (pesc0, pesc1)]
    for s in (1, -1):
        if not sem_bracos:
            om = j((s * c["ombro"], 0, 1.375), c["braco"] * 1.15)
            bm_ = j((s * 0.33, 0, 1.38), (c["braco"], c["braco"] * 0.95))
            co = j((s * 0.47, 0, 1.38), c["cotovelo"])
            ab = j((s * 0.57, 0, 1.38), (c["cotovelo"] * 1.12, c["cotovelo"] * 1.0))
            pu = j((s * 0.705, 0, 1.38), (c["pulso"], c["pulso"] * 0.8))
            arestas += [(topo, om), (om, bm_), (bm_, co), (co, ab), (ab, pu)]
        qd = j((s * 0.105, 0, 0.88), c["coxa"] * 1.05)
        cx = j((s * 0.11, -0.005, 0.72), c["coxa"])
        jo = j((s * 0.11, 0, 0.53), c["joelho"])
        pa = j((s * 0.11, 0.012, 0.38), (c["joelho"] * 1.05, c["joelho"] * 1.12))   # panturrilha
        to = j((s * 0.11, 0, 0.14), c["tornozelo"])
        arestas += [(quad, qd), (qd, cx), (cx, jo), (jo, pa), (pa, to)]
    bm = bmesh.new()
    vs = [bm.verts.new(p) for p, _ in juntas]
    for a, b in arestas:
        bm.edges.new((vs[a], vs[b]))
    o = _novo_obj("corpo", bm)
    mod = o.modifiers.new("skin", "SKIN")
    mod.branch_smoothing = 0.6
    mod.use_smooth_shade = True
    for i, (_, r) in enumerate(juntas):
        sv = o.data.skin_vertices[0].data[i]
        sv.radius = r
        sv.use_root = (i == 0)
    sub = o.modifiers.new("sub", "SUBSURF")
    sub.levels = 1
    sub.render_levels = 1
    _aplicar_mods(o)
    _suave(o, 80)
    k.pintar(o, cor)
    pesos_suaves(o)
    return o


def casca(corpo, nome, cor, planos, afastar=0.014):
    """Roupa = pedaço do corpo recortado por PLANOS (corte reto e limpo, sem
    serrilhado), afastado pela normal. planos: [(ponto, normal), ...] — fica o lado
    em que (p - ponto)·normal <= 0. Os pesos vêm junto (deforma igual ao corpo)."""
    o = corpo.copy()
    o.data = corpo.data.copy()
    o.name = nome
    bpy.context.scene.collection.objects.link(o)
    bm = bmesh.new()
    bm.from_mesh(o.data)
    for ponto, normal in planos:
        geo = bm.verts[:] + bm.edges[:] + bm.faces[:]
        bmesh.ops.bisect_plane(bm, geom=geo, plane_co=Vector(ponto), plane_no=Vector(normal), clear_outer=True)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.normal_update()
    for v in bm.verts:
        v.co += v.normal * afastar
    bm.to_mesh(o.data)
    bm.free()
    _suave(o, 80)
    return k.pintar(o, cor)


def faixa(corpo, nome, cor, planos, afastar=0.022):
    """Faixa colada ao corpo (cós, cinto, barra, punho, listra): anel recortado da
    própria malha por planos, um pouco mais afastado que a roupa."""
    return casca(corpo, nome, cor, planos, afastar)


def entre_z(z0, z1):
    return [((0, 0, z1), (0, 0, 1)), ((0, 0, z0), (0, 0, -1))]


def ate_x(x):
    """Só até |x| <= x (corta as mangas/braços nos dois lados)."""
    return [((x, 0, 0), (1, 0, 0)), ((-x, 0, 0), (-1, 0, 0))]


def braco_entre(s, x0, x1):
    """Trecho do braço do lado s entre |x| = x0 e x1 (punho, barra de manga)."""
    return [((s * x1, 0, 0), (s, 0, 0)), ((s * x0, 0, 0), (-s, 0, 0)), ((0, 0, 1.26), (0, 0, -1))]


def anel(nome, raio, espessura, pos, cor, eixo="Z", seg=14, achatado=1.0, rx=None):
    """Punho/barra/cós: toro (opcionalmente oval: rx = raio em x)."""
    rot = {"Z": (0, 0, 0), "X": (0, 90, 0), "Y": (90, 0, 0)}[eixo]
    o = k.toro(nome, raio, espessura, pos, cor, rot=rot, seg=seg, seg_menor=4)
    if rx:
        o.scale = (rx / raio, 1, 1) if eixo == "Z" else (1, 1, 1)
        k._aplicar(o)
    if achatado != 1.0:
        o.scale = (1, 1, achatado) if eixo == "Z" else (achatado, 1, 1)
        k._aplicar(o)
    return o


# ---------------------------------------------------------------- cabeça
def cabeca(pele="pele_2", z=1.67, tam=1.0, mandibula=0.22, queixo=0.02, bochecha=0.0):
    """Crânio esculpido: esfera deformada (nuca cheia, mandíbula afinando para o
    queixo, bochechas) + pescoço encaixado embaixo."""
    bpy.ops.mesh.primitive_uv_sphere_add(segments=26, ring_count=18, radius=0.17 * tam, location=(0, 0, z))
    o = bpy.context.active_object
    o.name = "cabeca"
    for v in o.data.vertices:
        p = v.co.copy()                            # local: origem no centro da cabeça
        h = p.z / (0.17 * tam)                     # -1 (queixo) .. 1 (topo)
        # cabeça um pouco mais alta que larga, nuca para trás
        p.z *= 1.1
        if p.y > 0:
            p.y *= 1.08
        if h < 0.1:
            t = (0.1 - h) / 1.1
            p.x *= 1.0 - mandibula * t                 # mandíbula afina
            if p.y < 0:
                p.y -= queixo * t                       # queixo um pouco à frente
            p.y *= 1.0 - 0.15 * t
        # bochechas
        if -0.6 < h < 0.15 and p.y < 0:
            p.x *= 1.0 + bochecha * math.cos((h + 0.22) * 4.0)
        # rosto levemente achatado na frente (olhos ficam bem assentados)
        if p.y < -0.12 * tam and h > -0.3:
            p.y = -0.12 * tam + (p.y + 0.12 * tam) * 0.55
        v.co = p
    _suave(o, 80)
    return k.pintar(o, pele)


def olhos(z=1.675, sep=0.068, tam=1.0, iris="azul_tormenta", pele="pele_2", cilio=False, y_face=-0.152, olhar=(0.0, 0.0),
          palpebra=0.35, cor_cilio="preto", inclina=0.0):
    """Olhos cartunescos: branco (oval), íris, pupila, dois brilhos, pálpebra de
    cima na cor da pele (dá expressão: 0 aberto .. 1 fechado) e linha de cílio."""
    pecas = []
    for s in (1, -1):
        x = s * sep
        r = 0.04 * tam
        base = Vector((x, y_face, z))
        br = k.esfera("olho_branco", r, base, "branco", escala=(0.85, 0.55, 1.15), segmentos=12, aneis=8)
        pecas.append(br)
        frente = base + Vector((olhar[0] * s * 0.0 + olhar[0] * 0.012, -r * 0.5, olhar[1] * 0.012))
        pecas.append(k.esfera("iris", r * 0.58, frente, iris, escala=(0.85, 0.35, 1.0), segmentos=10, aneis=6))
        pecas.append(k.esfera("pupila", r * 0.32, frente + Vector((0, -0.006, 0)), "preto", escala=(0.85, 0.35, 1.0), segmentos=8, aneis=4))
        pecas.append(k.esfera("brilho", r * 0.16, frente + Vector((0.011, -0.011, 0.014)), "branco", segmentos=6, aneis=4))
        pecas.append(k.esfera("brilho2", r * 0.08, frente + Vector((-0.008, -0.011, -0.012)), "branco", segmentos=6, aneis=4))
        # pálpebra superior: casca de esfera na cor da pele, cobrindo o topo do olho
        pal = mundo(k.esfera("palpebra", r * 1.07, base + Vector((0, 0.002, 0)), pele, escala=(0.9, 0.6, 1.2), segmentos=12, aneis=8))
        bm = bmesh.new()
        bm.from_mesh(pal.data)
        corte = base.z + r * 1.2 * (1.0 - 2.0 * palpebra) * 0.95
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < corte], context="VERTS")
        bm.to_mesh(pal.data)
        bm.free()
        pecas.append(pal)
        # cílio / linha da pálpebra
        lin = mundo(k.toro("cilio", r * 0.92, 0.0065 * (1.4 if cilio else 1.0), base + Vector((0, -0.004, r * 0.02)), cor_cilio,
                           rot=(90, 0, 0), seg=16, seg_menor=4))
        bm = bmesh.new()
        bm.from_mesh(lin.data)
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < base.z + r * 0.35], context="VERTS")
        bm.to_mesh(lin.data)
        bm.free()
        for v in lin.data.vertices:
            v.co.z = base.z + (v.co.z - base.z) * 1.25
        pecas.append(lin)
        if cilio:
            for i, a in enumerate((50, 25)):
                cil = k.caixa("cilio_ponta", (0.022, 0.006, 0.008), base + Vector((s * r * 0.95, -0.01, r * 0.85 - i * 0.012)), cor_cilio,
                              rot=(0, s * -a, 0))
                pecas.append(cil)
    return pecas


def sobrancelhas(z=1.735, sep=0.07, cor="cabelo_castanho", grossura=1.0, angulo=8.0, y_face=-0.16, arco=0.012):
    pecas = []
    for s in (1, -1):
        # arco: cilindro curto inclinado + ponta afinando
        o = k.cilindro("sobrancelha", 0.011 * grossura, 0.07, (s * sep, y_face, z), cor, lados=6, rot=(0, 90, 0), raio_topo=0.006 * grossura)
        for v in o.data.vertices:
            dx = v.co.x - s * sep
            v.co.z += arco * (1 - (dx / 0.035) ** 2)
        o.rotation_euler = (0, math.radians(s * -angulo), 0)
        k._aplicar(o)
        o.location = (0, 0, 0)
        pecas.append(o)
    return pecas


def nariz(z=1.63, pele="pele_3", tam=1.0, y_face=-0.165, forma="redondo"):
    if forma == "pontudo":
        o = k.cilindro("nariz", 0.022 * tam, 0.05 * tam, (0, y_face - 0.015, z), pele, lados=8, rot=(80, 0, 0), raio_topo=0.008 * tam)
    else:
        o = k.esfera("nariz", 0.026 * tam, (0, y_face - 0.008, z), pele, escala=(1.0, 0.9, 0.85), segmentos=10, aneis=8)
    return [o]


def boca(z=1.585, y_face=-0.155, largura=0.05, sorriso=0.6, cor="preto", labio=None):
    """Boca: arco (sorriso > 0) ou reta, com lábio inferior opcional."""
    o = mundo(k.toro("boca", largura, 0.0075, (0, y_face, z + largura * sorriso * 0.6), cor, rot=(90, 0, 0), seg=18, seg_menor=4))
    bm = bmesh.new()
    bm.from_mesh(o.data)
    # mantém só o arco de baixo
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z > z + largura * sorriso * 0.6 - largura * 0.55], context="VERTS")
    bm.to_mesh(o.data)
    bm.free()
    zc = z + largura * sorriso * 0.6
    for v in o.data.vertices:
        v.co.z = zc + (v.co.z - zc) * max(0.25, sorriso)
    pecas = [o]
    if labio:
        pecas.append(k.esfera("labio", largura * 0.45, (0, y_face + 0.006, z - largura * 0.15), labio, escala=(1.2, 0.45, 0.4), segmentos=10, aneis=6))
    return pecas


def orelhas(z=1.655, pele="pele_2", x=0.165):
    pecas = []
    for s in (1, -1):
        o = k.esfera("orelha", 0.042, (s * x, 0.015, z), pele, escala=(0.45, 0.85, 1.15), segmentos=8, aneis=6)
        o.rotation_euler = (0, 0, math.radians(s * -15))
        k._aplicar(o)
        pecas.append(o)
        pecas.append(k.esfera("orelha_dentro", 0.024, (s * (x + 0.012), 0.005, z), _escurecer(pele), escala=(0.3, 0.6, 0.85), segmentos=6, aneis=4))
    return pecas


def _escurecer(pele):
    return {"pele_1": "pele_2", "pele_2": "pele_3", "pele_3": "pele_4", "pele_4": "pele_4"}.get(pele, pele)


def mecha(nome, base, ponta, raio, cor, curva=(0, 0, 0), lados=6, segmentos=4):
    """Mecha de cabelo: tubo cônico curvo (de base a ponta, arqueando por `curva`)."""
    pecas = []
    base, ponta, curva = Vector(base), Vector(ponta), Vector(curva)
    pts = []
    for i in range(segmentos + 1):
        t = i / segmentos
        pts.append(base.lerp(ponta, t) + curva * math.sin(t * math.pi))
    bm = bmesh.new()
    aneis = []
    for i, p in enumerate(pts):
        t = i / segmentos
        r = raio * (1 - t) ** 0.8 + 0.002
        d = (pts[min(i + 1, segmentos)] - pts[max(i - 1, 0)]).normalized()
        a = d.orthogonal().normalized()
        b = d.cross(a)
        anel_v = [bm.verts.new(p + (a * math.cos(j * math.tau / lados) + b * math.sin(j * math.tau / lados)) * r) for j in range(lados)]
        aneis.append(anel_v)
    for i in range(segmentos):
        for j in range(lados):
            bm.faces.new((aneis[i][j], aneis[i][(j + 1) % lados], aneis[i + 1][(j + 1) % lados], aneis[i + 1][j]))
    bm.faces.new(list(reversed(aneis[0])))
    bm.faces.new(aneis[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = _novo_obj(nome, bm)
    _suave(o, 70)
    return k.pintar(o, cor)


def cabelo(estilo, cor, z=1.67, tam=1.0):
    """Estilos: 'topete' (curto com topete de vento), 'rabo' (franja + rabo de cavalo
    alto), 'bagunca' (mechas para todo lado), 'raspado' (só a calota)."""
    pecas = []
    cz = z + 0.03
    calota = mundo(k.esfera("calota", 0.182 * tam, (0, 0.018, cz + 0.018), cor, escala=(1.03, 1.06, 0.92), segmentos=16, aneis=10))
    bm = bmesh.new()
    bm.from_mesh(calota.data)
    # corta a calota na testa (frente) e na altura das orelhas (lados)
    def fora(v):
        p = v.co
        testa = p.y < -0.05 * tam and p.z < cz + 0.085 * tam
        lado = p.z < cz - 0.02 * tam and p.y < 0.07
        nuca = p.z < cz - 0.12 * tam
        return testa or lado or nuca
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if fora(v)], context="VERTS")
    bm.to_mesh(calota.data)
    bm.free()
    sol = calota.modifiers.new("esp", "SOLIDIFY")
    sol.thickness = 0.012
    _aplicar_mods(calota)
    _suave(calota, 70)
    pecas.append(calota)
    if estilo in ("topete", "bagunca"):
        # mechas para cima e para trás (vento), da testa ao alto da cabeça
        mechas = [((-0.06, -0.12, cz + 0.11), (-0.02, -0.07, cz + 0.27), (0.0, -0.03, 0.02), 0.045),
                  ((0.03, -0.12, cz + 0.12), (0.09, -0.04, cz + 0.25), (0.0, -0.02, 0.02), 0.042),
                  ((0.07, -0.08, cz + 0.14), (0.15, 0.03, cz + 0.2), (0.02, 0.0, 0.03), 0.038),
                  ((-0.11, -0.06, cz + 0.12), (-0.17, 0.04, cz + 0.17), (-0.01, 0.0, 0.03), 0.036),
                  ((0.0, -0.02, cz + 0.17), (0.02, 0.12, cz + 0.22), (0, 0, 0.04), 0.05)]
        if estilo == "bagunca":
            mechas += [((0.12, 0.05, cz + 0.08), (0.21, 0.1, cz + 0.02), (0, 0, 0.03), 0.034),
                       ((-0.12, 0.06, cz + 0.08), (-0.21, 0.12, cz + 0.03), (0, 0, 0.03), 0.034)]
        for i, (b, p, cv, r) in enumerate(mechas):
            pecas.append(mecha(f"mecha{i}", b, p, r * tam, cor, curva=cv))
        # costeletas
        for s in (1, -1):
            pecas.append(k.esfera("costeleta", 0.03, (s * 0.158, -0.035, cz - 0.045), cor, escala=(0.4, 0.9, 1.4), segmentos=8, aneis=6))
    elif estilo == "rabo":
        # franja varrida de lado + volume nas laterais + rabo de cavalo alto
        for i, (b, p, cv, r) in enumerate([
                ((0.1, -0.13, cz + 0.12), (-0.05, -0.17, cz + 0.03), (0, -0.03, 0.03), 0.05),
                ((0.05, -0.14, cz + 0.13), (-0.11, -0.15, cz + 0.06), (0, -0.03, 0.02), 0.045),
                ((0.13, -0.1, cz + 0.08), (0.15, -0.13, cz - 0.05), (0.02, -0.01, 0), 0.04)]):
            pecas.append(mecha(f"franja{i}", b, p, r * tam, cor, curva=cv))
        for s in (1, -1):
            pecas.append(mecha("lateral", (s * 0.15, 0.0, cz + 0.05), (s * 0.165, -0.02, cz - 0.13), 0.05, cor, curva=(s * 0.02, 0, 0)))
        pecas.append(k.toro("elastico", 0.04, 0.014, (0, 0.17, cz + 0.12), "coral", rot=(65, 0, 0), seg=10, seg_menor=4))
        pecas.append(mecha("rabo", (0, 0.18, cz + 0.13), (0, 0.33, cz - 0.2), 0.07, cor, curva=(0, 0.09, 0.05), segmentos=7))
        pecas.append(mecha("rabo2", (0.02, 0.19, cz + 0.12), (0.05, 0.3, cz - 0.15), 0.045, cor, curva=(0.02, 0.07, 0.04)))
    return pecas


# ---------------------------------------------------------------- mãos e pés
def mao(lado, s, cor="cinza_tecido", punho=None, z=1.38):
    """Luva com palma, quatro dedos levemente curvados e polegar."""
    x0 = s * 0.715
    pecas = [k.caixa("palma", (0.1, 0.085, 0.045), (s * 0.765, -0.005, z), cor, bevel=0.022)]
    for i, dy in enumerate((-0.03, -0.01, 0.01, 0.03)):
        comp = (0.055, 0.062, 0.058, 0.048)[i]
        f = k.cilindro("dedo", 0.0125, comp, (s * (0.815 + comp / 2), dy, z - 0.004), cor, lados=7, rot=(0, 90, 0), raio_topo=0.011)
        f.rotation_euler.y += math.radians(s * 12)
        k._aplicar(f)
        pecas.append(f)
    pecas.append(k.cilindro("polegar", 0.015, 0.05, (s * 0.765, -0.055, z + 0.005), cor, lados=7, rot=(65, 0, s * 30), raio_topo=0.012))
    if punho:
        pecas.append(anel("punho_luva", 0.044, 0.012, (x0, 0, z), punho, eixo="X", seg=12))
    return pecas


def calcado(lado, s, cor="couro", sola="preto", cano=0.0, biqueira=None, cadarco="branco", tenis=False):
    """Bota/tênis esculpido: corpo arredondado, bico mais largo, sola grossa,
    lingueta e cadarço; cano opcional (bota)."""
    x = s * 0.11
    pecas = []
    bpy.ops.mesh.primitive_cube_add(size=1, location=(x, -0.045, 0.065))
    o = bpy.context.active_object
    o.name = "calcado"
    o.scale = (0.15 if not tenis else 0.16, 0.29, 0.11)
    k._aplicar(o)
    for v in o.data.vertices:                     # coordenadas locais (centro do calçado)
        t = max(0.0, min(1.0, (-v.co.y / 0.145 + 1) / 2))   # 0 calcanhar .. 1 bico
        # bico mais largo e mais baixo, calcanhar estreito e alto
        v.co.x *= 0.85 + 0.25 * t
        if v.co.z > 0.0:
            v.co.z -= 0.04 * t ** 1.5
    sub = o.modifiers.new("sub", "SUBSURF")
    sub.levels = 1
    _aplicar_mods(o)
    _suave(o, 70)
    k.pintar(o, cor)
    pecas.append(o)
    so = k.caixa("sola", (0.14 if not tenis else 0.155, 0.285, 0.026), (x, -0.045, 0.014), sola, bevel=0.011)
    pecas.append(so)
    if biqueira:
        pecas.append(k.esfera("biqueira", 0.07, (x, -0.17, 0.05), biqueira, escala=(1.05, 0.9, 0.65), segmentos=10, aneis=6))
    # lingueta + cadarço (3 traços)
    pecas.append(k.caixa("lingueta", (0.06, 0.08, 0.02), (x, -0.08, 0.115), cor, bevel=0.008, rot=(-25, 0, 0)))
    for i in range(3):
        pecas.append(k.caixa("cadarco", (0.07, 0.012, 0.008), (x, -0.06 - i * 0.03, 0.118 - i * 0.012), cadarco, rot=(-25, 0, 0)))
    if cano > 0:
        pecas.append(k.cilindro("cano", 0.062, cano, (x, 0.005, 0.1 + cano / 2), cor, lados=12, raio_topo=0.066))
        pecas.append(anel("borda_cano", 0.066, 0.012, (x, 0.005, 0.1 + cano), cor, seg=12))
    return pecas


# ---------------------------------------------------------------- roupas prontas
def camiseta(corpo, cor, manga="curta", gola=None, barra=None, afastar=0.012, listra=None):
    """Camiseta/camisa: tronco (quadril até a base do pescoço) e mangas, com barra,
    punhos e uma listra opcional no peito (z0, z1, cor), todos colados ao corpo."""
    lim = {"curta": 0.37, "longa": 0.69, "nenhuma": 0.21}[manga]
    pecas = [casca(corpo, "camisa", cor, entre_z(0.96, 1.452) + ate_x(lim), afastar + 0.006)]
    if gola:
        pecas.append(anel("gola", 0.06, 0.016, (0, 0.006, 1.447), gola, seg=16, rx=0.066))
    pecas.append(faixa(corpo, "barra", barra or cor, entre_z(0.96, 0.995) + ate_x(0.3), afastar + 0.014))
    if manga != "nenhuma":
        for s in (1, -1):
            pecas.append(faixa(corpo, "punho_manga", barra or cor, braco_entre(s, lim - 0.035, lim), afastar + 0.014))
    if listra:
        z0, z1, cl = listra
        pecas.append(faixa(corpo, "listra", cl, entre_z(z0, z1) + ate_x(0.23), afastar + 0.012))
    return pecas


def calca(corpo, cor, comprimento="longa", cinto=None, fivela="dourado", bolsos=True, barra=None, afastar=0.012, z_cintura=1.1):
    zmin = {"longa": 0.16, "bermuda": 0.5, "corsario": 0.32}[comprimento]
    pecas = [casca(corpo, "calca", cor, entre_z(zmin, z_cintura), afastar)]
    if cinto:
        pecas.append(faixa(corpo, "cinto", cinto, entre_z(z_cintura - 0.05, z_cintura - 0.008), afastar + 0.012))
        pecas.append(k.caixa("fivela", (0.055, 0.015, 0.04), (0, -0.142, z_cintura - 0.029), fivela, bevel=0.006))
    pecas.append(faixa(corpo, "barra_calca", barra or _escurecer_tecido(cor), entre_z(zmin, zmin + 0.04), afastar + 0.01))
    for s in (1, -1):
        if bolsos:
            pecas.append(k.caixa("bolso", (0.07, 0.012, 0.06), (s * 0.09, -0.126, 0.95), _escurecer_tecido(cor), bevel=0.008, rot=(-6, 0, s * 10)))
            pecas.append(k.caixa("bolso_tras", (0.08, 0.01, 0.08), (s * 0.08, 0.128, 0.93), _escurecer_tecido(cor), bevel=0.01))
    return pecas


def _escurecer_tecido(cor):
    return {"jeans": "jeans", "verde_militar": "folha_escura", "cinza_tecido": "pedra_media", "couro": "madeira_escura",
            "teal": "teal_escuro", "areia": "madeira_clara", "vermelho": "coral", "roxo": "azul_tormenta"}.get(cor, cor)


def jaqueta(corpo, cor, gola_alta=False, ziper="metal_claro", forro=None, punho=None, faixas=None, aberta=False, comprimento=0.94):
    """Jaqueta: tronco e mangas até o pulso, mais grossa que a camisa, com gola,
    zíper, punhos, barra e bolsos; faixas: [(z, cor)] (ex.: refletivas)."""
    pecas = [casca(corpo, "jaqueta", cor, entre_z(comprimento, 1.455) + ate_x(0.69), 0.024)]
    g = 0.09 if gola_alta else 0.076
    pecas.append(anel("gola", g, 0.026 if gola_alta else 0.02, (0, 0.008, 1.45 + (0.015 if gola_alta else 0)), forro or cor, seg=16, rx=g + 0.01))
    if gola_alta:
        pecas.append(anel("gola2", g - 0.005, 0.02, (0, 0.008, 1.49), forro or cor, seg=16, rx=g + 0.005))
    if ziper and not aberta:
        pecas.append(k.caixa("ziper", (0.012, 0.008, 1.42 - comprimento), (0, -0.155, (1.42 + comprimento) / 2), ziper))
        pecas.append(k.caixa("puxador", (0.016, 0.006, 0.03), (0, -0.161, 1.42), ziper, bevel=0.004))
    pecas.append(faixa(corpo, "barra", punho or cor, entre_z(comprimento, comprimento + 0.04) + ate_x(0.3), 0.034))
    for s in (1, -1):
        pecas.append(faixa(corpo, "punho", punho or cor, braco_entre(s, 0.645, 0.69), 0.034))
        pecas.append(k.caixa("bolso_j", (0.09, 0.012, 0.07), (s * 0.1, -0.165, comprimento + 0.11), _escurecer_tecido(cor), bevel=0.01))
    for z, cf in (faixas or []):
        pecas.append(faixa(corpo, "faixa", cf, entre_z(z - 0.018, z + 0.018), 0.03))
    return pecas


def montar_humano(c, corpo_tipo, pele, cabelo_estilo, cabelo_cor, olhos_cor="azul_tormenta", feminino=False,
                  sobrancelha_ang=8.0, sorriso=0.6, labio=None, nariz_forma="redondo", sem_cabeca=False, expressao_palpebra=0.32):
    """Corpo + cabeça humana completa. Retorna o objeto do corpo (para as roupas)."""
    corpo = corpo_base(corpo_tipo, pele)
    c.pele(corpo)
    if sem_cabeca:
        return corpo
    for o in [cabeca(pele, mandibula=0.28 if feminino else 0.2, queixo=0.025 if feminino else 0.03, bochecha=0.05 if feminino else 0.02)]:
        c.add(o, "Head")
    for o in olhos(iris=olhos_cor, pele=pele, cilio=feminino, tam=1.08 if feminino else 1.0, palpebra=expressao_palpebra):
        c.add(o, "Head")
    for o in sobrancelhas(cor=cabelo_cor, grossura=0.75 if feminino else 1.0, angulo=sobrancelha_ang):
        c.add(o, "Head")
    for o in nariz(pele=_escurecer(pele) if not feminino else pele, tam=0.85 if feminino else 1.0, forma=nariz_forma):
        c.add(o, "Head")
    for o in boca(sorriso=sorriso, labio=labio, largura=0.042 if feminino else 0.05):
        c.add(o, "Head")
    for o in orelhas(pele=pele):
        c.add(o, "Head")
    if cabelo_estilo:
        for o in cabelo(cabelo_estilo, cabelo_cor):
            c.add(o, "Head")
    return corpo
