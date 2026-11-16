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


def bau_ventania_01():
    corpo = [
        k.caixa("caixa", (L, P, A), (0, 0, A / 2), "teal_escuro", bevel=0.05),
        k.caixa("faixa_base", (L + 0.03, P + 0.03, 0.08), (0, 0, 0.06), "amarelo_sol"),
        k.caixa("faixa_topo", (L + 0.03, P + 0.03, 0.06), (0, 0, A - 0.05), "amarelo_sol"),
        k.caixa("fechadura", (0.16, 0.05, 0.14), (0, -P / 2 - 0.02, A - 0.1), "dourado"),
        # interior dourado (só aparece com a tampa aberta)
        k.caixa("interior", (L - 0.12, P - 0.12, 0.02), (0, 0, A + 0.005), "amarelo_sol"),
    ]
    for x in (-L / 2, L / 2):
        for y in (-P / 2, P / 2):
            corpo.append(k.caixa("canto", (0.1, 0.1, A + 0.02), (x * 0.98, y * 0.98, A / 2), "amarelo_sol"))
    oc = k.unir(corpo, "bau_ventania_01")
    oc["interacao"] = "abrir"
    oc["visibilidade_m"] = 150.0

    tampa_partes = [
        k.caixa("tampa_caixa", (L + 0.04, P + 0.04, 0.18), (0, 0, A + 0.09), "teal", bevel=0.05),
        k.caixa("forro", (L - 0.08, P - 0.08, 0.02), (0, 0, A - 0.002), "teal_escuro"),
        k.toro("emblema", 0.11, 0.03, (0, -P / 2 - 0.03, A + 0.1), "coral", rot=(90, 0, 0), seg=10, seg_menor=4),
        k.esfera("emblema_centro", 0.05, (0.03, -P / 2 - 0.04, A + 0.12), "amarelo_sol", segmentos=8, aneis=6),
        k.cilindro("emblema_cauda", 0.025, 0.22, (-0.13, -P / 2 - 0.03, A + 0.03), "coral", lados=6, rot=(0, 70, 0)),
    ]
    tampa = k.unir(tampa_partes, "tampa")
    # origem da tampa na dobradiça (fundo superior), para girar em X
    tampa.data.transform(__import__("mathutils").Matrix.Translation([-c for c in DOBRADICA]))
    tampa.location = DOBRADICA
    tampa.parent = oc

    acao = bpy.data.actions.new("abrir")
    acao.use_fake_user = True
    tampa.animation_data_create()
    tampa.animation_data.action = acao
    for quadro, ang in ((1, 0.0), (6, -40.0), (14, -115.0), (18, -105.0)):
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
