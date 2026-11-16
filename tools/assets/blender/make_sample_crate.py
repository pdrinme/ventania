"""Gera o asset de exemplo do pipeline: um caixote de madeira simples, original.

Serve para testar a cadeia Blender -> GLB -> validação -> importação na Godot.
Não é um asset final de jogo. Geometria e textura são geradas por código.

Uso:
    blender -b -P tools/assets/blender/make_sample_crate.py
    # ou, com o módulo bpy do PyPI:
    python tools/assets/blender/make_sample_crate.py

Saída: assets_src/baus_coletaveis/caixote_exemplo_01.blend
"""

import os

import bpy

RAIZ = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
SAIDA = os.path.join(RAIZ, "assets_src", "baus_coletaveis", "caixote_exemplo_01.blend")
TEX = 128  # atlas pequeno: faixas de cor (madeira clara, madeira escura, metal)


def criar_atlas():
    img = bpy.data.images.new("T_caixote_exemplo_01", TEX, TEX, alpha=False)
    faixas = [(0.80, 0.55, 0.30), (0.55, 0.33, 0.16), (0.55, 0.58, 0.62), (0.95, 0.80, 0.25)]
    px = []
    for y in range(TEX):
        for x in range(TEX):
            r, g, b = faixas[min(x * 4 // TEX, 3)]
            veio = 0.06 if (y // 6) % 2 else 0.0  # veio de madeira simples
            px += [max(r - veio, 0), max(g - veio, 0), max(b - veio, 0), 1.0]
    img.pixels = px
    img.pack()
    return img


def material(img):
    m = bpy.data.materials.new("M_caixote_exemplo_01")
    m.use_nodes = True
    nos = m.node_tree.nodes
    bsdf = nos.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = 0.9
    tex = nos.new("ShaderNodeTexImage")
    tex.image = img
    tex.interpolation = "Closest"
    m.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    return m


def mapear_uv(obj, faixa):
    """Achata todas as UVs do objeto no centro da faixa de cor do atlas (0..3)."""
    u = (faixa + 0.5) / 4.0
    for laco in obj.data.uv_layers.active.data:
        laco.uv = (u, 0.5 + (laco.uv[1] - 0.5) * 0.9)


def caixa(nome, tamanho, posicao, mat, faixa):
    bpy.ops.mesh.primitive_cube_add(size=1, location=posicao)
    o = bpy.context.active_object
    o.name = nome
    o.scale = tamanho
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o.data.materials.append(mat)
    mapear_uv(o, faixa)
    return o


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    mat = material(criar_atlas())
    partes = [
        caixa("corpo", (1.0, 0.7, 0.6), (0, 0, 0.30), mat, 0),
        caixa("tampa", (1.04, 0.74, 0.12), (0, 0, 0.66), mat, 1),
        caixa("cinta_esq", (0.08, 0.76, 0.74), (-0.32, 0, 0.37), mat, 2),
        caixa("cinta_dir", (0.08, 0.76, 0.74), (0.32, 0, 0.37), mat, 2),
        caixa("fecho", (0.12, 0.04, 0.12), (0, -0.38, 0.55), mat, 3),
    ]
    bpy.ops.object.select_all(action="DESELECT")
    for p in partes:
        p.select_set(True)
    bpy.context.view_layer.objects.active = partes[0]
    bpy.ops.object.join()
    corpo = bpy.context.active_object
    corpo.name = "caixote_exemplo_01"
    corpo["categoria"] = "baus_coletaveis"   # vira metadado na Godot
    corpo["interacao"] = "abrir"

    # colisão simplificada: uma caixa única, sufixo -colonly (a Godot cria StaticBody3D)
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 0.36))
    col = bpy.context.active_object
    col.name = "caixote_exemplo_01-colonly"
    col.scale = (1.04, 0.76, 0.72)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

    os.makedirs(os.path.dirname(SAIDA), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=SAIDA, compress=True)
    print("SALVO:", os.path.relpath(SAIDA, RAIZ))


if __name__ == "__main__":
    main()
