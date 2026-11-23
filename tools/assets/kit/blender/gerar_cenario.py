"""Gera a vegetação e as rochas estilizadas da ilha (direção de arte 1.3: formas
orgânicas, levemente tortas, copas fofas em "nuvens" de folhas, troncos curvos com
base alargada, pedras facetadas e robustas). Tudo procedural e original.

Variações (o mapa sorteia e agrupa):
  arvore_redonda_01  folhosa de copa larga, tronco torto com dois galhos
  arvore_redonda_02  "pirulito" alto e torto, copa em duas bolas
  arvore_redonda_03  folhosa de outono (laranja/amarelo), baixa e larga
  pinheiro_01        pinheiro de camadas caídas, ponta torta
  pinheiro_02        pinheiro alto e fino
  arbusto_01         moita fofa (sem colisão: dá para se esconder)
  arbusto_02         moita com flores
  flores_01          tufo de flores coloridas (decoração)
  grama_01           tufo de capim alto (decoração)
  pedra_01           pedra grande facetada com uma pedra menor ao lado
  pedra_02           pedra alta inclinada (lasca)
  pedra_03           seixos pequenos (decoração)

Uso: python tools/assets/kit/blender/gerar_cenario.py [id ...]
"""

import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kit_comum as k  # noqa: E402

import bmesh  # noqa: E402  (depois do bpy, que o kit_comum importa)
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402


def _obj(nome, bm):
    me = bpy.data.meshes.new(nome)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(nome, me)
    bpy.context.scene.collection.objects.link(o)
    return o


def tronco(nome, pontos, r0, r1, cor, lados=7, raiz=1.45):
    """Tubo que passa pelos pontos, afinando de r0 a r1; a base se alarga (raízes)."""
    pts = [Vector(p) for p in pontos]
    n = len(pts)
    bm = bmesh.new()
    aneis = []
    for i, p in enumerate(pts):
        t = i / (n - 1)
        r = r0 + (r1 - r0) * t
        if i == 0:
            r *= raiz
        d = (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized()
        a = d.orthogonal().normalized()
        b = d.cross(a)
        anel = []
        for j in range(lados):
            ang = j * math.tau / lados
            # raízes: a base fica "estrelada"
            rr = r * (1.0 + (0.22 * math.cos(ang * 3) if i == 0 else 0.0))
            anel.append(bm.verts.new(p + (a * math.cos(ang) + b * math.sin(ang)) * rr))
        aneis.append(anel)
    for i in range(n - 1):
        for j in range(lados):
            bm.faces.new((aneis[i][j], aneis[i][(j + 1) % lados], aneis[i + 1][(j + 1) % lados], aneis[i + 1][j]))
    bm.faces.new(list(reversed(aneis[0])))
    bm.faces.new(aneis[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = _obj(nome, bm)
    k._suavizar(o, 70)
    return k.pintar(o, cor)


def copa(nome, raio, pos, cor, semente=0, escala=(1, 1, 0.95), achatar=0.72, sub=3, ondas=0.18):
    """Nuvem de folhas: esfera com calombos suaves (não ruído por vértice: as
    ondulações são contínuas, a silhueta fica "fofa") e a parte de baixo achatada."""
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=sub, radius=raio, location=(0, 0, 0))
    o = bpy.context.active_object
    o.name = nome
    s = semente * 1.7
    for v in o.data.vertices:
        nv = v.co.normalized()
        d = 1.0 + ondas * math.sin(3.1 * nv.x + s) * math.cos(2.7 * nv.y + 2 * s) \
            + ondas * 0.6 * math.sin(4.3 * nv.z + 3 * s + nv.x * 2.0)
        c = v.co * d
        if c.z < 0:
            c.z *= achatar
        v.co = Vector((c.x * escala[0], c.y * escala[1], c.z * escala[2])) + Vector(pos)
    k._suavizar(o, 80)
    return k.pintar(o, cor)


def cone_camada(nome, raio, altura, pos, cor, semente=0, inclinar=(0.0, 0.0), lados=9, pontas=0.18):
    """Camada de pinheiro: cone com a borda recortada em pontas caídas."""
    rnd = random.Random(semente)
    bm = bmesh.new()
    base = []
    for j in range(lados * 2):
        ang = j * math.tau / (lados * 2) + rnd.uniform(-0.05, 0.05)
        ponta = j % 2 == 0
        r = raio * (1.0 if ponta else 0.78)
        z = -pontas * raio * (1.0 if ponta else 0.2)
        base.append(bm.verts.new((math.cos(ang) * r, math.sin(ang) * r, z)))
    meio = []
    for j in range(lados):
        ang = j * math.tau / lados + 0.2
        meio.append(bm.verts.new((math.cos(ang) * raio * 0.5, math.sin(ang) * raio * 0.5, altura * 0.45)))
    topo = bm.verts.new((inclinar[0], inclinar[1], altura))
    centro_baixo = bm.verts.new((0, 0, altura * 0.12))
    nb = len(base)
    for j in range(lados):
        a, b, c = base[2 * j], base[(2 * j + 1) % nb], base[(2 * j + 2) % nb]
        m0, m1 = meio[j], meio[(j + 1) % lados]
        bm.faces.new((a, b, m0))
        bm.faces.new((b, c, m1))
        bm.faces.new((b, m1, m0))
        bm.faces.new((m0, m1, topo))
    for j in range(nb):
        bm.faces.new((base[(j + 1) % nb], base[j], centro_baixo))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for v in bm.verts:
        # leve torção: as camadas não ficam todas alinhadas
        v.co.x += v.co.z * inclinar[0] * 0.2
        v.co += Vector(pos)
    o = _obj(nome, bm)
    k._suavizar(o, 50)
    return k.pintar(o, cor)


def rocha(nome, raio, pos, cor, semente=0, escala=(1, 1, 0.8), forca=0.28, sub=2):
    """Pedra facetada: icosfera com cortes planos (faces grandes e chanfradas)."""
    rnd = random.Random(semente)
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=sub, radius=raio, location=(0, 0, 0))
    o = bpy.context.active_object
    o.name = nome
    # "lascas": empurra para dentro tudo o que passa de alguns planos aleatórios
    planos = []
    for _ in range(7):
        n = Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-0.3, 1))).normalized()
        planos.append((n, raio * rnd.uniform(1.0 - forca, 0.95)))
    for v in o.data.vertices:
        c = v.co.copy()
        for n, dist in planos:
            e = c.dot(n) - dist
            if e > 0:
                c -= n * e
        if c.z < -raio * 0.35:
            c.z = -raio * 0.35
        v.co = Vector((c.x * escala[0], c.y * escala[1], c.z * escala[2])) + Vector(pos)
    k._suavizar(o, 28)
    return k.pintar(o, cor)


FOLHAS = ("folha_media", "folha_clara", "folha_escura")


# ------------------------------------------------------------------ árvores

def arvore_redonda_01():
    t = tronco("tronco", [(0, 0, 0), (0.12, 0.02, 1.1), (-0.12, 0.05, 2.2), (0.06, 0.0, 3.2)], 0.34, 0.15, "tronco")
    g1 = tronco("galho1", [(-0.1, 0.04, 2.0), (-0.6, 0.18, 2.6), (-1.05, 0.3, 3.15)], 0.13, 0.06, "tronco", lados=5, raiz=1.0)
    g2 = tronco("galho2", [(0.02, 0.0, 2.5), (0.55, -0.2, 3.0), (0.95, -0.38, 3.45)], 0.12, 0.05, "tronco", lados=5, raiz=1.0)
    copas = [
        copa("c1", 1.45, (0.05, 0.05, 3.95), "folha_media", 1),
        copa("c2", 1.0, (-1.15, 0.32, 3.45), "folha_escura", 2),
        copa("c3", 1.0, (1.05, -0.42, 3.6), "folha_clara", 3),
        copa("c4", 0.82, (0.25, 0.65, 4.65), "folha_clara", 4),
        copa("c5", 0.75, (-0.35, -0.7, 4.45), "folha_media", 5),
    ]
    o = k.unir([t, g1, g2] + copas, "arvore_redonda_01")
    o["coleta"] = "madeira"
    o["visibilidade_m"] = 260.0
    k.colisao_caixa("arvore_redonda_01", (0.6, 0.6, 3.0), (0, 0, 1.5))


def arvore_redonda_02():
    t = tronco("tronco", [(0, 0, 0), (0.25, 0, 1.3), (0.05, 0.1, 2.6), (-0.3, 0.05, 3.9), (-0.15, 0, 4.9)], 0.26, 0.12, "tronco", lados=6)
    copas = [
        copa("c1", 1.15, (-0.2, 0.0, 5.3), "folha_clara", 7, escala=(1, 1, 1.0)),
        copa("c2", 0.8, (0.45, 0.2, 4.45), "folha_media", 8),
        copa("c3", 0.62, (-0.35, 0.1, 6.35), "folha_clara", 9, escala=(1, 1, 1.1)),
    ]
    o = k.unir([t] + copas, "arvore_redonda_02")
    o["coleta"] = "madeira"
    o["visibilidade_m"] = 260.0
    k.colisao_caixa("arvore_redonda_02", (0.5, 0.5, 3.0), (0.1, 0, 1.5))


def arvore_redonda_03():
    t = tronco("tronco", [(0, 0, 0), (-0.1, 0.05, 0.9), (0.08, 0, 1.8), (0.0, 0.0, 2.4)], 0.4, 0.2, "madeira_escura")
    g1 = tronco("galho1", [(0, 0, 1.7), (0.7, 0.1, 2.3), (1.3, 0.2, 2.6)], 0.14, 0.06, "madeira_escura", lados=5, raiz=1.0)
    g2 = tronco("galho2", [(0, 0, 1.9), (-0.7, -0.2, 2.4), (-1.25, -0.25, 2.75)], 0.13, 0.06, "madeira_escura", lados=5, raiz=1.0)
    copas = [
        copa("c1", 1.35, (0, 0, 3.25), "laranja", 11, escala=(1.15, 1.1, 0.95)),
        copa("c2", 0.95, (1.35, 0.25, 2.85), "amarelo_sol", 12, escala=(1, 1, 0.95)),
        copa("c3", 0.95, (-1.3, -0.25, 2.95), "coral", 13, escala=(1, 1, 0.95)),
        copa("c4", 0.75, (0.1, 0.4, 3.85), "amarelo_sol", 14),
    ]
    o = k.unir([t, g1, g2] + copas, "arvore_redonda_03")
    o["coleta"] = "madeira"
    o["visibilidade_m"] = 260.0
    k.colisao_caixa("arvore_redonda_03", (0.7, 0.7, 2.4), (0, 0, 1.2))


def _pinheiro(nome, camadas, tronco_alt, inclinacao):
    t = tronco("tronco", [(0, 0, 0), (0.05, 0, tronco_alt * 0.5), (inclinacao * 0.3, 0, tronco_alt)], 0.26, 0.16, "tronco", lados=6)
    partes = [t]
    z = tronco_alt * 0.55
    n = len(camadas)
    for i, (r, h) in enumerate(camadas):
        frac = i / max(1, n - 1)
        cor = "folha_escura" if i % 2 == 0 else "teal_escuro" if i == n - 1 else "folha_media"
        dx = inclinacao * frac
        partes.append(cone_camada(f"camada{i}", r, h, (dx, 0, z), cor, semente=i + len(nome),
                                  inclinar=(inclinacao * 0.35 * (1 if i == n - 1 else 0.3), 0.0)))
        z += h * 0.52
    return partes


def pinheiro_01():
    o = k.unir(_pinheiro("p1", [(1.7, 1.7), (1.35, 1.5), (1.0, 1.35), (0.65, 1.2)], 1.3, 0.35), "pinheiro_01")
    o["coleta"] = "madeira"
    o["visibilidade_m"] = 260.0
    k.colisao_caixa("pinheiro_01", (0.5, 0.5, 1.6), (0, 0, 0.8))   # só o tronco: dá para passar sob os galhos


def pinheiro_02():
    o = k.unir(_pinheiro("p2", [(1.3, 1.6), (1.1, 1.5), (0.9, 1.4), (0.7, 1.3), (0.45, 1.2)], 1.6, -0.45), "pinheiro_02")
    o["coleta"] = "madeira"
    o["visibilidade_m"] = 260.0
    k.colisao_caixa("pinheiro_02", (0.45, 0.45, 1.8), (0, 0, 0.9))


# ------------------------------------------------------------------ arbustos e plantas

def arbusto_01():
    partes = [
        copa("b1", 0.62, (0, 0, 0.5), "folha_media", 21, achatar=0.3),
        copa("b2", 0.46, (0.58, 0.15, 0.36), "folha_clara", 22, achatar=0.3),
        copa("b3", 0.44, (-0.52, -0.2, 0.34), "folha_escura", 23, achatar=0.3),
        copa("b4", 0.34, (0.1, -0.5, 0.3), "folha_clara", 24, achatar=0.3, sub=2),
    ]
    o = k.unir(partes, "arbusto_01")
    o["visibilidade_m"] = 130.0  # sem colisão: dá para se esconder dentro


def arbusto_02():
    rnd = random.Random(31)
    partes = [
        copa("b1", 0.55, (0, 0, 0.45), "folha_escura", 31, achatar=0.3),
        copa("b2", 0.42, (0.5, -0.1, 0.32), "folha_media", 32, achatar=0.3),
        copa("b3", 0.38, (-0.45, 0.2, 0.3), "folha_media", 33, achatar=0.3, sub=2),
    ]
    for i in range(9):
        a = rnd.uniform(0, math.tau)
        el = rnd.uniform(0.2, 1.1)
        p = (math.cos(a) * 0.5 * math.cos(el) * 1.1, math.sin(a) * 0.5 * math.cos(el), 0.42 + math.sin(el) * 0.45)
        partes.append(k.esfera("flor", 0.07, p, "rosa" if i % 3 else "branco", escala=(1, 1, 0.6), segmentos=6, aneis=4))
    o = k.unir(partes, "arbusto_02")
    o["visibilidade_m"] = 130.0


def flores_01():
    rnd = random.Random(41)
    cores = ("rosa", "amarelo_sol", "branco", "roxo", "coral")
    partes = []
    for i in range(5):
        a = rnd.uniform(0, math.tau)
        d = rnd.uniform(0.05, 0.4)
        x, y = math.cos(a) * d, math.sin(a) * d
        h = rnd.uniform(0.25, 0.5)
        partes.append(k.cilindro("caule", 0.012, h, (x, y, h / 2), "folha_escura", lados=4, rot=(rnd.uniform(-10, 10), rnd.uniform(-10, 10), 0)))
        cor = cores[i % len(cores)]
        for p in range(5):
            ap = p * math.tau / 5
            partes.append(k.esfera("petala", 0.035, (x + math.cos(ap) * 0.04, y + math.sin(ap) * 0.04, h), cor,
                                   escala=(1, 1, 0.4), segmentos=5, aneis=3))
        partes.append(k.esfera("miolo", 0.025, (x, y, h + 0.01), "amarelo_sol" if cor != "amarelo_sol" else "laranja", segmentos=5, aneis=3))
    for i in range(4):
        a = i * math.tau / 4 + 0.3
        partes.append(copa("folhas", 0.14, (math.cos(a) * 0.2, math.sin(a) * 0.2, 0.06), "folha_media", 40 + i, achatar=0.3, sub=2))
    o = k.unir(partes, "flores_01")
    o["visibilidade_m"] = 70.0


def grama_01():
    rnd = random.Random(51)
    partes = []
    for i in range(11):
        a = rnd.uniform(0, math.tau)
        d = rnd.uniform(0.0, 0.25)
        h = rnd.uniform(0.35, 0.7)
        inc = rnd.uniform(8, 28)
        partes.append(k.cilindro("folha", 0.035, h, (math.cos(a) * d, math.sin(a) * d, h * 0.45),
                                 ("grama", "folha_clara", "folha_media")[i % 3], lados=3, raio_topo=0.0,
                                 rot=(inc * math.sin(a), -inc * math.cos(a), rnd.uniform(0, 90))))
    o = k.unir(partes, "grama_01")
    o["visibilidade_m"] = 60.0


# ------------------------------------------------------------------ rochas

def pedra_01():
    grande = rocha("grande", 1.0, (0, 0, 0.5), "pedra_media", 4, escala=(1.5, 1.15, 0.9))
    topo = rocha("topo", 0.6, (-0.25, 0.1, 1.05), "pedra_clara", 6, escala=(1.3, 1.0, 0.6))
    pequena = rocha("pequena", 0.55, (1.25, -0.5, 0.25), "pedra_clara", 5, escala=(1.2, 1, 0.8))
    musgo = copa("musgo", 0.45, (-0.55, 0.45, 0.95), "folha_escura", 61, escala=(1.4, 1.1, 0.35), sub=2)
    o = k.unir([grande, topo, pequena, musgo], "pedra_01")
    o["coleta"] = "pedra"
    o["visibilidade_m"] = 220.0
    k.colisao_da_malha(o, "pedra_01")   # forma convexa da própria pedra


def pedra_02():
    alta = rocha("alta", 0.8, (0, 0, 1.1), "pedra_escura", 71, escala=(1.0, 0.75, 2.0), forca=0.32)
    base = rocha("base", 0.75, (0.45, 0.2, 0.3), "pedra_media", 72, escala=(1.4, 1.1, 0.6))
    lasca = rocha("lasca", 0.45, (-0.6, -0.3, 0.25), "pedra_clara", 73, escala=(1.0, 0.8, 0.9))
    for o in (alta,):
        for v in o.data.vertices:           # inclina a lasca (encosta torta)
            v.co.x += (v.co.z - 0.3) * 0.22
    o = k.unir([alta, base, lasca], "pedra_02")
    o["coleta"] = "pedra"
    o["visibilidade_m"] = 240.0
    k.colisao_da_malha(o, "pedra_02")


def pedra_03():
    partes = []
    rnd = random.Random(81)
    for i in range(5):
        a = rnd.uniform(0, math.tau)
        d = rnd.uniform(0.1, 0.6)
        r = rnd.uniform(0.12, 0.26)
        partes.append(rocha("seixo", r, (math.cos(a) * d, math.sin(a) * d, r * 0.3), ("pedra_clara", "pedra_media")[i % 2], 82 + i,
                            escala=(1.3, 1.0, 0.6)))
    o = k.unir(partes, "pedra_03")
    o["visibilidade_m"] = 80.0


GERADORES = {f.__name__: f for f in (arvore_redonda_01, arvore_redonda_02, arvore_redonda_03, pinheiro_01, pinheiro_02,
                                     arbusto_01, arbusto_02, flores_01, grama_01, pedra_01, pedra_02, pedra_03)}


def main():
    for asset_id in sys.argv[1:] or list(GERADORES):
        k.nova_cena()
        GERADORES[asset_id]()
        k.salvar("cenario", asset_id)


if __name__ == "__main__":
    main()
