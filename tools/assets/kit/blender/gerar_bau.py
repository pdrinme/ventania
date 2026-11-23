"""Gera o baú de loot do projeto: caixa arredondada azul-petróleo com faixas
amarelas e um emblema de redemoinho de vento (tema "Ventania"), com a tampa
articulada e a animação "abrir".

Uso: python tools/assets/kit/blender/gerar_bau.py
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy  # noqa: E402

import kit_comum as k  # noqa: E402

L, P, A = 1.1, 0.7, 0.5   # largura, profundidade, altura do corpo
DOBRADICA = (0, P / 2, A)


def _arco(nome, raio, comp, z, cor, achatar=0.72, lados=12):
    """Meio cilindro deitado no eixo X (tampa abaulada), base plana em z."""
    o = k.cilindro(nome, raio, comp, (0, 0, z), cor, lados=lados, rot=(0, 90, 0))
    for v in o.data.vertices:
        if v.co.z < z:
            v.co.z = z
        v.co.z = z + (v.co.z - z) * achatar
    return o


def bau_ventania_01():
    """Baú de tábuas pintadas de teal com cantoneiras e cintas douradas, rebites,
    tampa abaulada com o emblema de vento e alça; levemente torto (estilo do kit)."""
    corpo = [
        k.caixa("caixa", (L, P, A), (0, 0, A / 2), "teal_escuro", bevel=0.04),
        k.caixa("faixa_base", (L + 0.03, P + 0.03, 0.08), (0, 0, 0.06), "amarelo_sol", bevel=0.01),
        k.caixa("faixa_topo", (L + 0.03, P + 0.03, 0.06), (0, 0, A - 0.05), "amarelo_sol", bevel=0.01),
        k.caixa("fechadura", (0.16, 0.05, 0.15), (0, -P / 2 - 0.02, A - 0.1), "dourado", bevel=0.015),
        k.caixa("buraco", (0.03, 0.02, 0.06), (0, -P / 2 - 0.05, A - 0.11), "preto"),
        # interior dourado (só aparece com a tampa aberta)
        k.caixa("interior", (L - 0.12, P - 0.12, 0.02), (0, 0, A + 0.005), "amarelo_sol"),
    ]
    # tábuas: frestas horizontais na frente e atrás
    for z in (0.19, 0.31):
        for y in (-P / 2 - 0.003, P / 2 + 0.003):
            corpo.append(k.caixa("fresta", (L - 0.2, 0.01, 0.012), (0, y, z), "preto"))
    for x in (-L / 2, L / 2):
        for y in (-P / 2, P / 2):
            corpo.append(k.caixa("canto", (0.1, 0.1, A + 0.02), (x * 0.98, y * 0.98, A / 2), "amarelo_sol", bevel=0.015))
    # dobradiças: ligam corpo e tampa visualmente (eixo X, na borda de trás do topo)
    for x in (-L * 0.3, L * 0.3):
        corpo.append(k.cilindro("dobradica", 0.035, 0.16, (x, P / 2 + 0.01, A), "metal_escuro", lados=8, rot=(0, 90, 0)))
    oc = k.unir(corpo, "bau_ventania_01")
    oc["interacao"] = "abrir"
    oc["visibilidade_m"] = 150.0

    tampa_partes = [
        _arco("tampa_caixa", P / 2 + 0.02, L + 0.04, A, "teal"),
        _arco("cinta_e", P / 2 + 0.035, 0.07, A, "amarelo_sol"),
        _arco("cinta_d", P / 2 + 0.035, 0.07, A, "amarelo_sol"),
        k.caixa("forro", (L - 0.08, P - 0.08, 0.02), (0, 0, A + 0.002), "teal_escuro"),
        k.toro("emblema", 0.1, 0.028, (0, -P / 2 - 0.0, A + 0.1), "coral", rot=(70, 0, 0), seg=10, seg_menor=4),
        k.esfera("emblema_centro", 0.045, (0.03, -P / 2 - 0.01, A + 0.115), "amarelo_sol", segmentos=8, aneis=6),
        k.cilindro("emblema_cauda", 0.022, 0.2, (-0.13, -P / 2 + 0.01, A + 0.04), "coral", lados=6, rot=(0, 70, 0)),
        k.caixa("alca", (0.22, 0.05, 0.05), (0, -P / 2 - 0.045, A + 0.06), "dourado", bevel=0.01),
    ]
    # cintas nas pontas da tampa
    tampa_partes[1].location.x = -L * 0.38
    tampa_partes[2].location.x = L * 0.38
    tampa = k.unir(tampa_partes, "tampa")
    # origem da tampa na DOBRADIÇA (depois de juntar: a origem do objeto está em 0,0,0)
    k.origem_em(tampa, DOBRADICA)
    tampa.parent = oc
    # ponto que a mão do personagem alcança ao abrir (borda da frente da tampa)
    k.marcador("alca_tampa", (0, -P / 2 - 0.05, A + 0.12), pai=tampa)

    acao = bpy.data.actions.new("abrir")
    acao.use_fake_user = True
    tampa.animation_data_create()
    tampa.animation_data.action = acao
    # destrava (leve tranco), abre com aceleração, passa um pouco e assenta
    for quadro, ang in ((1, 0.0), (3, -4.0), (5, -2.0), (8, -35.0), (11, -85.0), (14, -112.0), (17, -103.0), (20, -106.0)):
        tampa.rotation_euler = (math.radians(ang), 0, 0)
        tampa.keyframe_insert("rotation_euler", index=0, frame=quadro)
    trilha = tampa.animation_data.nla_tracks.new()
    trilha.name = "abrir"
    trilha.strips.new("abrir", 1, acao)
    tampa.animation_data.action = None
    tampa.rotation_euler = (0, 0, 0)

    k.colisao_caixa("bau_ventania_01", (L, P, A + 0.18), (0, 0, (A + 0.18) / 2))


GERADORES = {"bau_ventania_01": bau_ventania_01}


def main():
    for asset_id in sys.argv[1:] or list(GERADORES):
        k.nova_cena()
        GERADORES[asset_id]()
        k.salvar("baus_coletaveis", asset_id)


if __name__ == "__main__":
    main()
