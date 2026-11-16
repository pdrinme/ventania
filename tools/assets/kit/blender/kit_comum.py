"""Funções compartilhadas pelos geradores do kit visual (Blender / bpy).

Estilo: formas simples, cantos arredondados, cor chapada vinda do atlas de
paleta (uma célula por peça). Tudo usa o material único M_paleta_ventania.
"""

import json
import math
import os

import bpy

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.abspath(os.path.join(AQUI, "..", "..", "..", ".."))
PALETA_JSON = os.path.join(AQUI, "..", "paleta.json")
PALETA_PNG = os.path.join(RAIZ, "game", "assets", "texturas_materiais", "paleta_ventania.png")
NOME_MATERIAL = "M_paleta_ventania"

with open(PALETA_JSON, encoding="utf-8") as _f:
    _P = json.load(_f)
_INDICE = {nome: i for i, (nome, _) in enumerate(_P["cores"])}
_POR_LINHA = _P["atlas_px"] // _P["celula_px"]


def nova_cena():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.unit_settings.system = "METRIC"
    bpy.context.scene.render.fps = 30
    bpy.context.scene["ventania_material_compartilhado"] = True


def material():
    m = bpy.data.materials.get(NOME_MATERIAL)
    if m:
        return m
    m = bpy.data.materials.new(NOME_MATERIAL)
    m.use_nodes = True
    nos = m.node_tree.nodes
    bsdf = nos.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = 1.0
    tex = nos.new("ShaderNodeTexImage")
    tex.interpolation = "Closest"
    img = bpy.data.images.load(PALETA_PNG, check_existing=True)
    tex.image = img
    m.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    return m


def uv_cor(nome_cor):
    """Centro da célula da cor no atlas (V invertido: linha 0 no topo da imagem)."""
    i = _INDICE[nome_cor]
    col, lin = i % _POR_LINHA, i // _POR_LINHA
    return ((col + 0.5) / _POR_LINHA, 1.0 - (lin + 0.5) / _POR_LINHA)


def pintar(obj, nome_cor):
    if not obj.data.uv_layers:
        obj.data.uv_layers.new()
    uv = uv_cor(nome_cor)
    for laco in obj.data.uv_layers.active.data:
        laco.uv = uv
    obj.data.materials.clear()
    obj.data.materials.append(material())
    return obj


def _ativo(o):
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o


def _aplicar(o, escala=True, rotacao=True):
    _ativo(o)
    bpy.ops.object.transform_apply(location=False, rotation=rotacao, scale=escala)


def _suavizar(o, angulo=40):
    _ativo(o)
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(angulo))


def _bevel(o, largura, segmentos=1):
    if largura <= 0:
        return
    mod = o.modifiers.new("bevel", "BEVEL")
    mod.width = largura
    mod.segments = segmentos
    mod.limit_method = "ANGLE"
    _ativo(o)
    bpy.ops.object.modifier_apply(modifier=mod.name)


def caixa(nome, tam, pos, cor, bevel=0.0, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=pos, rotation=[math.radians(r) for r in rot])
    o = bpy.context.active_object
    o.name = nome
    o.scale = tam
    _aplicar(o)
    _bevel(o, bevel)
    _suavizar(o, 30)
    return pintar(o, cor)


def cilindro(nome, raio, altura, pos, cor, lados=10, rot=(0, 0, 0), raio_topo=None):
    if raio_topo is None:
        bpy.ops.mesh.primitive_cylinder_add(vertices=lados, radius=raio, depth=altura, location=pos,
                                            rotation=[math.radians(r) for r in rot])
    else:
        bpy.ops.mesh.primitive_cone_add(vertices=lados, radius1=raio, radius2=raio_topo, depth=altura,
                                        location=pos, rotation=[math.radians(r) for r in rot])
    o = bpy.context.active_object
    o.name = nome
    _aplicar(o)
    _suavizar(o, 50)
    return pintar(o, cor)


def esfera(nome, raio, pos, cor, escala=(1, 1, 1), segmentos=12, aneis=8, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segmentos, ring_count=aneis, radius=raio, location=pos,
                                         rotation=[math.radians(r) for r in rot])
    o = bpy.context.active_object
    o.name = nome
    o.scale = escala
    _aplicar(o)
    _suavizar(o, 80)
    return pintar(o, cor)


def icoesfera(nome, raio, pos, cor, escala=(1, 1, 1), sub=1, ruido=0.0, semente=0):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=sub, radius=raio, location=pos)
    o = bpy.context.active_object
    o.name = nome
    if ruido:
        import random
        rnd = random.Random(semente)
        for v in o.data.vertices:
            f = 1.0 + rnd.uniform(-ruido, ruido)
            v.co = v.co * f
    o.scale = escala
    _aplicar(o)
    return pintar(o, cor)


def toro(nome, raio, espessura, pos, cor, rot=(0, 0, 0), seg=14, seg_menor=6):
    bpy.ops.mesh.primitive_torus_add(major_radius=raio, minor_radius=espessura, major_segments=seg,
                                     minor_segments=seg_menor, location=pos,
                                     rotation=[math.radians(r) for r in rot])
    o = bpy.context.active_object
    o.name = nome
    _aplicar(o)
    _suavizar(o, 80)
    return pintar(o, cor)


def unir(objs, nome):
    """Junta as peças em um objeto com a ORIGEM NO CENTRO DO MUNDO (0,0,0).

    Sem o transform_apply, o objeto herdaria a origem da primeira peça, e qualquer
    rotação/deslocamento posterior seria feito em torno do ponto errado (era a causa
    da tampa do baú solta e das construções desalinhadas com a colisão)."""
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = nome
    o.data.name = nome
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return o


def origem_em(obj, ponto):
    """Move a origem do objeto para `ponto` (mundo) sem mexer na geometria."""
    from mathutils import Matrix, Vector
    p = Vector(ponto) - obj.matrix_world.translation
    obj.data.transform(Matrix.Translation(-p))
    obj.location = obj.location + p


def colisao_caixa(nome, tam, pos, rot=(0, 0, 0), sufixo=""):
    """Caixa de colisão SÓLIDA (sufixo -convcolonly: a Godot cria um StaticBody3D com
    forma convexa). Formas convexas são sólidas por dentro; malhas de triângulos
    (-colonly) são ocas e deixam o personagem atravessar/prender em paredes finas."""
    bpy.ops.mesh.primitive_cube_add(size=1, location=pos, rotation=[math.radians(r) for r in rot])
    o = bpy.context.active_object
    o.name = f"{nome}{sufixo}-convcolonly"
    o.scale = tam
    _ativo(o)
    # grava tudo nos vértices (origem 0,0,0): não depende de como o importador
    # trata o deslocamento do nó de colisão
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return o


def colisao_convexa(nome, vertices, sufixo=""):
    """Colisão convexa a partir de pontos (ex.: pirâmide do telhado)."""
    malha = bpy.data.meshes.new(f"{nome}{sufixo}-col")
    malha.from_pydata([tuple(v) for v in vertices], [], [])
    o = bpy.data.objects.new(f"{nome}{sufixo}-convcolonly", malha)
    bpy.context.scene.collection.objects.link(o)
    # casca convexa real (com faces), para a Godot gerar a forma
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.convex_hull()
    bpy.ops.object.mode_set(mode="OBJECT")
    return o


def colisao_da_malha(obj, nome):
    """Cópia convexa da própria malha visual (ex.: pedra)."""
    c = obj.copy()
    c.data = obj.data.copy()
    c.name = f"{nome}-convcolonly"
    for k in list(c.keys()):
        del c[k]
    bpy.context.scene.collection.objects.link(c)
    return c


def marcador(nome, pos, pai=None):
    """Ponto de referência exportado como nó (ex.: empunhadura, cano, alça da tampa)."""
    from mathutils import Vector
    e = bpy.data.objects.new(nome, None)
    e.empty_display_size = 0.03
    bpy.context.scene.collection.objects.link(e)
    if pai is not None:
        e.parent = pai
        e.location = Vector(pos) - pai.matrix_world.translation
    else:
        e.location = pos
    return e


def salvar(categoria, asset_id):
    caminho = os.path.join(RAIZ, "assets_src", categoria, f"{asset_id}.blend")
    os.makedirs(os.path.dirname(caminho), exist_ok=True)
    # caminho relativo da paleta, para o .blend abrir em qualquer máquina
    for img in bpy.data.images:
        if img.filepath:
            img.filepath = bpy.path.relpath(img.filepath, start=os.path.dirname(caminho))
    bpy.ops.wm.save_as_mainfile(filepath=caminho, compress=True, relative_remap=True)
    print("SALVO:", os.path.relpath(caminho, RAIZ))
    return caminho
