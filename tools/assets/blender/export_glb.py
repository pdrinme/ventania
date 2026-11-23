"""Exporta um .blend para GLB pronto para a Godot, com checagens de orçamento.

Uso (Blender instalado):
    blender -b assets_src/<categoria>/<id>.blend -P tools/assets/blender/export_glb.py -- \
        --categoria <categoria> --id <id>

Uso (módulo `bpy` do PyPI, sem interface):
    python tools/assets/blender/export_glb.py --blend assets_src/<categoria>/<id>.blend \
        --categoria <categoria> --id <id>

Saída: game/assets/<categoria>/<id>.glb

Convenções esperadas na cena (ver docs/assets/PIPELINE.md):
  - Unidade: metro; escala 1; origem do objeto na base (pés / chão).
  - Objetos de colisão com sufixo "-col", "-colonly" ou "-convcolonly" (sufixos da Godot).
  - Objetos com sufixo "-noexport" são ignorados.
  - Propriedades customizadas viram metadados na Godot (export_extras).
  - Oclusão ambiente "assada" nos vértices (atributo de cor "Color", canal R): raios
    sobre o hemisfério de cada vértice contra a própria malha do asset. O shader do
    kit escurece cantos, dobras e encaixes com ela (volume sem textura e sem custo em
    tempo real). Desligue por objeto com a propriedade customizada "sem_ao" = 1.
"""

import argparse
import json
import os
import sys

import bpy

RAIZ = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
ORCAMENTOS = os.path.join(RAIZ, "tools", "assets", "budgets.json")


def _args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--blend", help="Arquivo .blend (só quando executado fora do Blender)")
    p.add_argument("--categoria", required=True)
    p.add_argument("--id", required=True)
    p.add_argument("--saida", help="Caminho do GLB (padrão: game/assets/<categoria>/<id>.glb)")
    p.add_argument("--aplicar-escala", action="store_true", help="Aplica escala/rotação pendentes em vez de falhar")
    return p.parse_args(argv)


def _contar_tris(obj, depsgraph):
    avaliado = obj.evaluated_get(depsgraph)
    malha = avaliado.to_mesh()
    try:
        malha.calc_loop_triangles()
        return len(malha.loop_triangles)
    finally:
        avaliado.to_mesh_clear()


def _eh_colisao(nome):
    return nome.endswith(("-col", "-colonly", "-convcolonly"))


def verificar(cena, orc, aplicar_escala):
    """Retorna (erros, avisos, estatísticas). Não modifica a cena, exceto com aplicar_escala."""
    erros, avisos = [], []
    depsgraph = bpy.context.evaluated_depsgraph_get()
    tris, materiais, imagens, ossos = 0, set(), {}, 0

    for obj in cena.objects:
        if obj.name.endswith("-noexport"):
            continue
        if obj.type == "MESH":
            escala_ok = all(abs(s - 1.0) < 1e-4 for s in obj.scale)
            if not escala_ok:
                if aplicar_escala:
                    bpy.ops.object.select_all(action="DESELECT")
                    obj.select_set(True)
                    bpy.context.view_layer.objects.active = obj
                    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
                    avisos.append(f"{obj.name}: escala aplicada automaticamente")
                else:
                    erros.append(f"{obj.name}: escala {tuple(round(s, 3) for s in obj.scale)} não aplicada (use Ctrl+A > Escala ou --aplicar-escala)")
            if _eh_colisao(obj.name):
                continue
            tris += _contar_tris(obj, depsgraph)
            for slot in obj.material_slots:
                if slot.material:
                    materiais.add(slot.material.name)
                    if slot.material.node_tree:
                        for no in slot.material.node_tree.nodes:
                            if no.type == "TEX_IMAGE" and no.image:
                                imagens[no.image.name] = tuple(no.image.size)
        elif obj.type == "ARMATURE":
            ossos = max(ossos, len(obj.data.bones))
        elif obj.type in {"CAMERA", "LIGHT"}:
            avisos.append(f"{obj.name}: {obj.type} não é exportado")

    if orc["max_tris"] and tris > orc["max_tris"]:
        erros.append(f"triângulos {tris} > orçamento {orc['max_tris']}")
    if len(materiais) > orc["max_materiais"]:
        erros.append(f"materiais {len(materiais)} > orçamento {orc['max_materiais']}: {sorted(materiais)}")
    for nome, (w, h) in imagens.items():
        if max(w, h) > orc["max_textura_px"]:
            erros.append(f"textura {nome} {w}x{h} > {orc['max_textura_px']}px")
        if w & (w - 1) or h & (h - 1):
            avisos.append(f"textura {nome} {w}x{h} não é potência de 2 (pior para compressão/mipmaps)")
    if ossos > orc["max_ossos"]:
        erros.append(f"ossos {ossos} > orçamento {orc['max_ossos']}")

    stats = {"tris": tris, "materiais": sorted(materiais), "texturas": imagens, "ossos": ossos}
    return erros, avisos, stats


def _assar_ao(raio=0.35, amostras=20):
    """AO por vértice (0 = fechado, 1 = aberto), gravado na cor "Color" (R=G=B).
    Usa a malha avaliada (modificadores aplicados) e uma BVH de TODOS os objetos
    visíveis da cena (peças encostadas também fazem sombra umas nas outras)."""
    import math
    import random
    from mathutils import Vector
    from mathutils.bvhtree import BVHTree
    dg = bpy.context.evaluated_depsgraph_get()
    malhas = [o for o in bpy.context.scene.objects if o.type == "MESH" and not _eh_colisao(o.name)]
    if not malhas:
        return
    # BVH única no espaço do mundo
    verts, polis = [], []
    for o in malhas:
        ev = o.evaluated_get(dg)
        m = ev.to_mesh()
        base = len(verts)
        mw = o.matrix_world
        verts += [mw @ v.co for v in m.vertices]
        polis += [[base + i for i in p.vertices] for p in m.polygons]
        ev.to_mesh_clear()
    bvh = BVHTree.FromPolygons(verts, polis, epsilon=0.0)
    rnd = random.Random(3)
    direcoes = []
    for i in range(amostras):
        # hemisfério cosseno (Fibonacci)
        u = (i + 0.5) / amostras
        r = math.sqrt(u)
        a = i * 2.399963
        direcoes.append(Vector((r * math.cos(a), r * math.sin(a), math.sqrt(1 - u))))
    for o in malhas:
        if o.get("sem_ao"):
            continue
        if o.modifiers:
            # AO na malha de repouso (base); modificadores de deformação (armadura) são aplicados no export
            pass
        m = o.data
        if "Color" in m.color_attributes:
            m.color_attributes.remove(m.color_attributes["Color"])
        cor = m.color_attributes.new("Color", "BYTE_COLOR", "POINT")
        mw = o.matrix_world
        nm = mw.to_3x3().inverted().transposed()
        for v in m.vertices:
            p = mw @ v.co
            n = (nm @ v.normal).normalized()
            # base ortonormal em volta da normal
            t = n.orthogonal().normalized()
            b = n.cross(t)
            livres = 0.0
            for d in direcoes:
                dw = (t * d.x + b * d.y + n * d.z).normalized()
                hit = bvh.ray_cast(p + n * 0.004, dw, raio)
                if hit[0] is None:
                    livres += 1.0
                else:
                    livres += min(1.0, hit[3] / raio) ** 2
            ao = livres / len(direcoes)
            ao = 0.35 + 0.65 * ao                      # nunca preto: só sombreado
            cor.data[v.index].color = (ao, ao, ao, 1.0)
        m.color_attributes.active_color = cor
        try:
            m.color_attributes.render_color_index = m.color_attributes.find("Color")
        except Exception:
            pass


def exportar(caminho, permite_animacao, material_compartilhado=False):
    """material_compartilhado: a cena usa só materiais que a Godot substitui na
    importação (ex.: M_paleta_ventania). Exporta o material pelo nome, sem
    imagens, para não duplicar a textura em cada GLB."""
    os.makedirs(os.path.dirname(caminho), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=caminho,
        export_format="GLB",
        use_selection=False,
        export_apply=True,            # aplica modificadores
        export_yup=True,              # Godot usa Y para cima
        export_cameras=False,
        export_lights=False,
        export_extras=True,           # propriedades customizadas -> metadados na Godot
        export_tangents=False,        # só ligar quando houver normal map
        export_draco_mesh_compression_enable=False,  # Godot não importa Draco
        # PNG/JPEG; a Godot recomprime para VRAM na importação. NONE = só o nome do material.
        export_image_format="NONE" if material_compartilhado else "AUTO",
        export_animations=permite_animacao,
        export_animation_mode="NLA_TRACKS",  # uma animação por trilha NLA (nome da trilha)
        export_optimize_animation_size=True,
        export_def_bones=True,        # só ossos de deformação
        export_unused_images=False,
        export_vertex_color="ACTIVE",  # AO assada (ver _assar_ao)
        export_all_vertex_colors=False,
    )


def main():
    a = _args()
    if a.blend:
        bpy.ops.wm.open_mainfile(filepath=os.path.abspath(a.blend))
    with open(ORCAMENTOS, encoding="utf-8") as f:
        cfg = json.load(f)
    if a.categoria not in cfg["categorias"]:
        sys.exit(f"ERRO: categoria desconhecida '{a.categoria}'. Válidas: {', '.join(cfg['categorias'])}")
    orc = cfg["categorias"][a.categoria]

    # objetos marcados para não exportar saem da cena exportada
    for obj in list(bpy.context.scene.objects):
        if obj.name.endswith("-noexport"):
            bpy.data.objects.remove(obj, do_unlink=True)

    erros, avisos, stats = verificar(bpy.context.scene, orc, a.aplicar_escala)
    for m in avisos:
        print("AVISO:", m)
    print("ESTATÍSTICAS:", json.dumps(stats, ensure_ascii=False))
    if erros:
        for m in erros:
            print("ERRO:", m)
        sys.exit(1)

    raio_ao = {"personagens": 0.07, "armas": 0.06, "mochilas_acessorios": 0.08, "baus_coletaveis": 0.12}.get(a.categoria, 0.45)
    _assar_ao(raio_ao)
    saida = a.saida or os.path.join(RAIZ, "game", "assets", a.categoria, f"{a.id}.glb")
    exportar(saida, orc["permite_animacao"], bool(bpy.context.scene.get("ventania_material_compartilhado")))
    print("EXPORTADO:", os.path.relpath(saida, RAIZ))


if __name__ == "__main__":
    main()
