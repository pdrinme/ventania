"""Gera as peças de construção do jogador (grade de 4 m) em 3 materiais.

Peças: parede, piso, rampa, teto x madeira, pedra, metal = 12 assets.
Design próprio do projeto:
  - madeira: tábuas verticais + travessas + diagonal (porta de celeiro)
  - pedra:   blocos irregulares sobre base de argamassa
  - metal:   chapa ondulada com moldura e rebites

Origem: centro da base da célula. Parede no plano XZ (frente em -Y), piso no
plano XY em z=0, rampa subindo de y=-2 (z=0) até y=+2 (z=4), teto como
pirâmide sobre a célula.

Uso: python tools/assets/kit/blender/gerar_construcoes.py [id ...]
"""

import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy  # noqa: E402

import kit_comum as k  # noqa: E402

CELULA = 4.0
ESP = 0.22  # espessura


def painel(material, largura=CELULA, comp=CELULA):
    """Peças de um painel no plano XZ: x em [-L/2, L/2], z em [0, comp], espessura em Y."""
    p, meio = [], largura / 2
    rnd = random.Random(7)
    if material == "madeira":
        n = 6
        w = largura / n
        for i in range(n):
            cor = "madeira_clara" if i % 2 == 0 else "madeira_media"
            p.append(k.caixa(f"tabua{i}", (w - 0.05, ESP, comp - 0.04), (-meio + w * (i + 0.5), 0, comp / 2), cor))
        for z in (comp * 0.18, comp * 0.82):
            p.append(k.caixa("travessa", (largura - 0.1, 0.08, 0.28), (0, -ESP / 2 - 0.03, z), "madeira_escura"))
        diag = math.hypot(largura - 0.4, comp * 0.64)
        ang = math.degrees(math.atan2(comp * 0.64, largura - 0.4))
        p.append(k.caixa("diagonal", (diag, 0.08, 0.24), (0, -ESP / 2 - 0.03, comp / 2), "madeira_escura", rot=(0, -ang, 0)))
    elif material == "pedra":
        p.append(k.caixa("argamassa", (largura, ESP * 0.8, comp), (0, 0, comp / 2), "pedra_escura"))
        linhas = 4
        h = comp / linhas
        for li in range(linhas):
            blocos = 3 if li % 2 == 0 else 4
            bw = largura / blocos
            for bi in range(blocos):
                cor = "pedra_clara" if (li + bi) % 2 == 0 else "pedra_media"
                prof = ESP + rnd.uniform(0.0, 0.08)
                p.append(k.caixa(f"bloco{li}_{bi}", (bw - 0.1, prof, h - 0.1),
                                 (-meio + bw * (bi + 0.5), -rnd.uniform(0, 0.03), h * (li + 0.5)), cor, bevel=0.0))
    elif material == "metal":
        p.append(k.caixa("chapa", (largura - 0.2, ESP * 0.6, comp - 0.2), (0, 0, comp / 2), "metal_escuro"))
        n = 7
        for i in range(n):
            x = -meio + 0.3 + i * (largura - 0.6) / (n - 1)
            p.append(k.caixa(f"onda{i}", (0.16, ESP * 0.9, comp - 0.3), (x, 0, comp / 2), "metal_claro"))
        for z in (0.1, comp - 0.1):
            p.append(k.caixa("moldura_h", (largura, ESP, 0.2), (0, 0, z), "metal_escuro"))
        for x in (-meio + 0.1, meio - 0.1):
            p.append(k.caixa("moldura_v", (0.2, ESP, comp), (x, 0, comp / 2), "metal_escuro"))
        for x in (-meio + 0.1, meio - 0.1):
            for z in (0.1, comp - 0.1):
                p.append(k.caixa("rebite", (0.1, 0.05, 0.1), (x, -ESP / 2 - 0.02, z), "amarelo_sol"))
    else:
        raise ValueError(material)
    return p


def _finalizar(objs, asset_id, rot_x=0.0, deslocar=(0, 0, 0)):
    o = k.unir(objs, asset_id)
    o.rotation_euler = (math.radians(rot_x), 0, 0)
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    o.data.transform(__import__("mathutils").Matrix.Translation(deslocar))
    o["peca_construcao"] = True
    return o


def parede(mat, asset_id):
    _finalizar(painel(mat), asset_id)
    k.colisao_caixa(asset_id, (CELULA, ESP, CELULA), (0, 0, CELULA / 2))


def piso(mat, asset_id):
    _finalizar(painel(mat), asset_id, rot_x=-90, deslocar=(0, -CELULA / 2, 0))
    k.colisao_caixa(asset_id, (CELULA, CELULA, ESP), (0, 0, 0))


def rampa(mat, asset_id):
    comp = math.hypot(CELULA, CELULA)
    _finalizar(painel(mat, comp=comp), asset_id, rot_x=-45, deslocar=(0, -CELULA / 2, 0))
    k.colisao_caixa(asset_id, (CELULA, comp, ESP), (0, 0, CELULA / 2), rot=(45, 0, 0))


def teto(mat, asset_id):
    cores = {"madeira": ("madeira_media", "madeira_escura"), "pedra": ("pedra_media", "pedra_escura"),
             "metal": ("metal_claro", "metal_escuro")}[mat]
    altura = 1.6
    piram = k.cilindro("piramide", CELULA / math.sqrt(2), altura, (0, 0, altura / 2), cores[0], lados=4,
                       rot=(0, 0, 45), raio_topo=0.0)
    beiral = k.caixa("beiral", (CELULA + 0.2, CELULA + 0.2, 0.14), (0, 0, 0.07), cores[1])
    topo = k.caixa("cumeeira", (0.3, 0.3, 0.25), (0, 0, altura - 0.05), cores[1])
    _finalizar([piram, beiral, topo], asset_id)
    k.colisao_caixa(asset_id, (CELULA, CELULA, 0.3), (0, 0, 0.15))


PECAS = {"parede": parede, "piso": piso, "rampa": rampa, "teto": teto}
MATERIAIS = ["madeira", "pedra", "metal"]
GERADORES = {f"{peca}_{mat}": (lambda p=peca, m=mat: PECAS[p](m, f"{p}_{m}")) for peca in PECAS for mat in MATERIAIS}


def main():
    ids = sys.argv[1:] or list(GERADORES)
    for asset_id in ids:
        k.nova_cena()
        GERADORES[asset_id]()
        k.salvar("construcoes", asset_id)


if __name__ == "__main__":
    main()
