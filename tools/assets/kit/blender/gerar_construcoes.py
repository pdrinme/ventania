"""Gera as peças de construção do jogador (grade de 4 m) em 3 materiais.

PADRÕES DA GRADE (Blender: Z para cima; Y para trás = -Z na Godot)
  Célula: x em [-2, 2], y em [-2, 2], nível z = 0 (origem = centro da base da célula).
  Piso:   placa z em [-0.10, +0.10]  -> o topo fica a 10 cm (degrau que a cápsula sobe).
  Parede: no plano y = 0 (borda da célula ao ser posicionada), z em [0, 4],
          espessura total 0.24 (y em [-0.12, +0.12]); todos os detalhes visuais
          ficam DENTRO dessa espessura, igual à colisão.
  Rampa:  a SUPERFÍCIE vai de (y=-2, z=0.10) até (y=+2, z=4.10): começa no topo de um
          piso e termina no topo do piso do andar de cima (45°). Placa de 0.20 abaixo.
  Teto:   pirâmide de base 4x4 em z = 0 e topo a 1.6 m (38,7°, dá para andar em cima).
  Colisão: formas CONVEXAS sólidas (-convcolonly), iguais ao volume visual.

Design próprio do projeto:
  madeira: tábuas verticais + travessas + diagonal (porta de celeiro)
  pedra:   blocos irregulares sobre base de argamassa
  metal:   chapa ondulada com moldura e rebites

Uso: python tools/assets/kit/blender/gerar_construcoes.py [id ...]
"""

import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

import kit_comum as k  # noqa: E402

CELULA = 4.0
ESP_PAREDE = 0.24
ESP_PISO = 0.20
ALTURA_PISO = 0.10                    # topo do piso acima do nível
TETO_ALTURA = 1.6
CHANFRO = 0.08                        # chanfro das bordas de cima dos pisos (colisão)


def painel(material, esp, largura=CELULA, comp=CELULA, superficie_frente=False):
    """Peças de um painel no plano XZ: x em [-L/2, L/2], z em [0, comp], espessura
    TOTAL `esp` em Y (centrada em 0). Nada passa de |y| > esp/2, e as faces externas
    ficam RENTES aos limites (iguais à colisão).
    superficie_frente: a face da frente (-Y) é a superfície de andar (pisos/rampas):
    as tábuas ficam rentes a ela e as travessas vão para trás (embaixo)."""
    p, meio, m = [], largura / 2, esp / 2
    rnd = random.Random(7)
    if material == "madeira":
        n = 6
        w = largura / n
        if superficie_frente:
            # pisos/rampas: tábuas na espessura TODA (topo e fundo iguais à colisão);
            # sarrafos transversais escuros marcam o desenho na superfície
            for i in range(n):
                cor = "madeira_clara" if i % 2 == 0 else "madeira_media"
                p.append(k.caixa(f"tabua{i}", (w - 0.04, esp, comp - 0.02), (-meio + w * (i + 0.5), 0, comp / 2), cor))
            for z in (comp * 0.1, comp * 0.9):
                p.append(k.caixa("sarrafo", (largura - 0.02, esp * 1.002, 0.22), (0, 0, z), "madeira_escura"))
        else:
            # paredes: tábuas rentes ao fundo, travessas e diagonal rentes à frente
            prof_tabua = esp * 0.62
            for i in range(n):
                cor = "madeira_clara" if i % 2 == 0 else "madeira_media"
                p.append(k.caixa(f"tabua{i}", (w - 0.04, prof_tabua, comp - 0.02), (-meio + w * (i + 0.5), m - prof_tabua / 2, comp / 2), cor))
            f = -(m - esp * 0.15)
            for z in (comp * 0.15, comp * 0.85):
                p.append(k.caixa("travessa", (largura - 0.04, esp * 0.3, 0.3), (0, f, z), "madeira_escura"))
            diag = math.hypot(largura - 0.5, comp * 0.70)
            ang = math.degrees(math.atan2(comp * 0.70, largura - 0.5))
            p.append(k.caixa("diagonal", (diag, esp * 0.3, 0.26), (0, f, comp / 2), "madeira_escura", rot=(0, -ang, 0)))
    elif material == "pedra":
        p.append(k.caixa("argamassa", (largura, esp * 0.6, comp), (0, 0, comp / 2), "pedra_escura"))
        linhas = 4
        h = comp / linhas
        for li in range(linhas):
            blocos = 3 if li % 2 == 0 else 4
            bw = largura / blocos
            for bi in range(blocos):
                cor = "pedra_clara" if (li + bi) % 2 == 0 else "pedra_media"
                prof = esp * rnd.uniform(0.82, 1.0)
                p.append(k.caixa(f"bloco{li}_{bi}", (bw - 0.08, prof, h - 0.08),
                                 (-meio + bw * (bi + 0.5), 0, h * (li + 0.5)), cor))
    elif material == "metal":
        p.append(k.caixa("chapa", (largura - 0.2, esp * 0.45, comp - 0.2), (0, 0, comp / 2), "metal_escuro"))
        n = 7
        for i in range(n):
            x = -meio + 0.32 + i * (largura - 0.64) / (n - 1)
            p.append(k.caixa(f"onda{i}", (0.16, esp * 0.8, comp - 0.3), (x, 0, comp / 2), "metal_claro"))
        for z in (0.1, comp - 0.1):
            p.append(k.caixa("moldura_h", (largura, esp, 0.2), (0, 0, z), "metal_escuro"))
        for x in (-meio + 0.1, meio - 0.1):
            p.append(k.caixa("moldura_v", (0.2, esp, comp), (x, 0, comp / 2), "metal_escuro"))
        for x in (-meio + 0.1, meio - 0.1):
            for z in (0.1, comp - 0.1):
                p.append(k.caixa("rebite", (0.1, esp * 1.02, 0.1), (x, 0, z), "amarelo_sol"))
    else:
        raise ValueError(material)
    return p


def _transformar(o, matriz):
    o.data.transform(matriz)
    o.data.update()


def _marcar(o, asset_id):
    o["peca_construcao"] = True
    o.name = asset_id
    o.data.name = asset_id


def parede(mat, asset_id):
    o = k.unir(painel(mat, ESP_PAREDE), asset_id)
    _marcar(o, asset_id)
    k.colisao_caixa(asset_id, (CELULA, ESP_PAREDE, CELULA), (0, 0, CELULA / 2))


def piso(mat, asset_id):
    # painel deitado: a altura do painel (z) vira a profundidade (y); espessura vira altura
    o = k.unir(painel(mat, ESP_PISO, superficie_frente=True), asset_id)
    _transformar(o, Matrix.Translation((0, 0, ALTURA_PISO - ESP_PISO / 2))
                 @ Matrix.Rotation(math.radians(-90), 4, "X") @ Matrix.Translation((0, 0, -CELULA / 2)))
    _marcar(o, asset_id)
    # colisão com as bordas de CIMA chanfradas a 45° (CHANFRO): a cápsula desliza
    # sobre a emenda rampa->piso e sobe do chão para o piso sem prender na quina viva
    h, c = CELULA / 2, CHANFRO
    topo, base, meio = ALTURA_PISO, ALTURA_PISO - ESP_PISO, ALTURA_PISO - CHANFRO
    pts = []
    for sx in (-1, 1):
        for sy in (-1, 1):
            pts += [(sx * h, sy * h, base), (sx * h, sy * h, meio), (sx * (h - c), sy * (h - c), topo)]
    k.colisao_convexa(asset_id, pts)


def rampa(mat, asset_id):
    comp = math.hypot(CELULA, CELULA)
    o = k.unir(painel(mat, ESP_PISO, comp=comp, superficie_frente=True), asset_id)
    # 1) painel deitado com o TOPO em z=0, centrado; 2) inclina 45° subindo para +Y;
    # 3) centro da superfície em (0, 0, 2.10)
    deitar = Matrix.Translation((0, 0, -ESP_PISO / 2)) @ Matrix.Rotation(math.radians(-90), 4, "X") @ Matrix.Translation((0, 0, -comp / 2))
    _transformar(o, Matrix.Translation((0, 0, CELULA / 2 + ALTURA_PISO)) @ Matrix.Rotation(math.radians(45), 4, "X") @ deitar)
    _marcar(o, asset_id)
    normal = Vector((0, -math.sin(math.radians(45)), math.cos(math.radians(45))))
    centro = Vector((0, 0, CELULA / 2 + ALTURA_PISO)) - normal * (ESP_PISO / 2)
    k.colisao_caixa(asset_id, (CELULA, comp, ESP_PISO), tuple(centro), rot=(45, 0, 0))


def teto(mat, asset_id):
    cores = {"madeira": ("madeira_media", "madeira_escura"), "pedra": ("pedra_media", "pedra_escura"),
             "metal": ("metal_claro", "metal_escuro")}[mat]
    piram = k.cilindro("piramide", CELULA / math.sqrt(2), TETO_ALTURA, (0, 0, TETO_ALTURA / 2), cores[0], lados=4,
                       rot=(0, 0, 45), raio_topo=0.0)
    beiral = k.caixa("beiral", (CELULA + 0.16, CELULA + 0.16, 0.12), (0, 0, 0.06), cores[1])
    topo = k.caixa("cumeeira", (0.3, 0.3, 0.2), (0, 0, TETO_ALTURA - 0.08), cores[1])
    o = k.unir([piram, beiral, topo], asset_id)
    _marcar(o, asset_id)
    h = CELULA / 2
    k.colisao_convexa(asset_id, [(-h, -h, 0), (h, -h, 0), (h, h, 0), (-h, h, 0),
                                 (-h, -h, 0.12), (h, -h, 0.12), (h, h, 0.12), (-h, h, 0.12),
                                 (0, 0, TETO_ALTURA)])


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
