"""Marcos surreais da ilha (um por POI), originais do projeto. São referências
visuais grandes, levemente tortas e bem-humoradas, que dão identidade a cada lugar
e ajudam a se orientar de longe:

  cata_vento_gigante_01   Mirante do Vento: mastro torto de 13 m com cata-vento
  cata_vento_helice_01      (hélice separada: gira no jogo)
  farol_torto_01          Porto Ferrugem: farol listrado inclinado, lanterna torta
  girassol_gigante_01     Fazenda Girassol: girassol de 11 m olhando para o lado
  cogumelos_gigantes_01   Acampamento Coral: três cogumelos gigantes (dá para subir)
  pedras_equilibradas_01  Pedreira Cinza: pilha de pedras impossível

Uso: python tools/assets/kit/blender/gerar_marcos.py [id ...]
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kit_comum as k  # noqa: E402
import gerar_cenario as gc  # noqa: E402


def cata_vento_gigante_01():
    # mastro de madeira torto, com escoras e uma plaquinha
    mastro = gc.tronco("mastro", [(0, 0, 0), (0.3, 0, 4), (-0.2, 0.15, 8), (0.25, 0, 12.6)], 0.42, 0.2, "madeira_media", lados=8)
    partes = [mastro]
    for a in (0, 120, 240):
        r = math.radians(a)
        partes.append(gc.tronco("escora", [(math.cos(r) * 2.2, math.sin(r) * 2.2, 0), (math.cos(r) * 0.3, math.sin(r) * 0.3, 3.4)],
                                0.14, 0.1, "madeira_escura", lados=5, raiz=1.2))
    partes.append(k.cilindro("cubo", 0.45, 0.6, (0.25, -0.3, 12.6), "pedra_escura", lados=10, rot=(90, 0, 0)))
    partes.append(k.caixa("placa", (1.6, 0.08, 0.7), (0.2, -0.45, 3.2), "amarelo_sol", bevel=0.03, rot=(0, 6, 0)))
    partes.append(k.caixa("placa_borda", (1.7, 0.06, 0.8), (0.2, -0.41, 3.2), "madeira_escura", rot=(0, 6, 0)))
    # cauda (leme) atrás, para o vento
    partes.append(k.caixa("leme_haste", (0.12, 2.4, 0.12), (0.25, 1.2, 12.6), "madeira_escura"))
    partes.append(k.caixa("leme", (0.08, 1.2, 1.4), (0.25, 2.4, 12.7), "coral", bevel=0.02, rot=(8, 0, 0)))
    o = k.unir(partes, "cata_vento_gigante_01")
    o["visibilidade_m"] = 600.0
    k.colisao_caixa("cata_vento_gigante_01", (0.8, 0.8, 12.6), (0.05, 0, 6.3))


def cata_vento_helice_01():
    """Hélice com 4 pás curvas coloridas; centro na origem, gira em torno de Y (Blender)."""
    partes = [k.esfera("miolo", 0.5, (0, 0, 0), "amarelo_sol", segmentos=12, aneis=8)]
    cores = ("teal", "coral", "amarelo_sol", "roxo")
    for i in range(4):
        a = i * 90
        r = math.radians(a)
        # pá: caixa fina torcida, afastada do centro
        partes.append(k.caixa(f"pa{i}", (0.9, 0.06, 3.0), (math.sin(r) * 1.9, 0, math.cos(r) * 1.9), cores[i],
                              bevel=0.05, rot=(0, a, 0)))
        partes.append(k.caixa(f"aba{i}", (0.8, 0.06, 1.2), (math.sin(r) * 2.6 + math.cos(r) * 0.6, -0.2, math.cos(r) * 2.6 - math.sin(r) * 0.6),
                              cores[(i + 1) % 4], bevel=0.04, rot=(-20, a, 0)))
    o = k.unir(partes, "cata_vento_helice_01")
    o["visibilidade_m"] = 600.0


def farol_torto_01():
    partes = []
    n = 7
    for i in range(n):
        t = i / n
        z = i * 1.7
        dx = 0.12 * i * i / n                      # inclina cada vez mais (torto)
        r0 = 1.9 - 0.85 * t
        r1 = 1.9 - 0.85 * (i + 1) / n
        partes.append(k.cilindro(f"anel{i}", r0, 1.72, (dx, 0, z + 0.85), "vermelho" if i % 2 == 0 else "branco",
                                 lados=14, raio_topo=r1, rot=(0, 2.5 * t * 4, 0)))
    topo_x, topo_z = 0.12 * n, n * 1.7
    partes.append(k.cilindro("varanda", 1.45, 0.25, (topo_x, 0, topo_z + 0.1), "pedra_escura", lados=14))
    partes.append(k.toro("grade", 1.35, 0.05, (topo_x, 0, topo_z + 0.8), "pedra_escura", seg=20, seg_menor=4))
    partes.append(k.cilindro("lanterna", 0.85, 1.4, (topo_x + 0.1, 0, topo_z + 0.95), "lente", lados=10, rot=(0, 6, 0)))
    partes.append(k.cilindro("chapeu", 1.15, 0.9, (topo_x + 0.25, 0, topo_z + 2.05), "vermelho", lados=10, raio_topo=0.15, rot=(0, 10, 8)))
    partes.append(k.esfera("bolinha", 0.22, (topo_x + 0.45, 0, topo_z + 2.55), "amarelo_sol", segmentos=8, aneis=6))
    partes.append(k.caixa("porta", (0.9, 0.2, 1.7), (0, -1.85, 0.85), "madeira_escura", bevel=0.05))
    for i, z in enumerate((3.4, 6.8, 10.2)):
        partes.append(k.caixa("janela", (0.45, 0.2, 0.6), (0.12 * (z / 1.7) ** 2 / n, -1.9 + 0.8 * z / topo_z, z), "lente", bevel=0.04))
    o = k.unir(partes, "farol_torto_01")
    o["visibilidade_m"] = 600.0
    k.colisao_caixa("farol_torto_01", (2.6, 2.6, 6.0), (0.1, 0, 3.0))
    k.colisao_caixa("farol_torto_01", (1.9, 1.9, 6.4), (0.5, 0, 9.0), sufixo="_2")


def girassol_gigante_01():
    caule = gc.tronco("caule", [(0, 0, 0), (0.4, 0, 3.5), (0.2, 0.2, 7), (1.2, 0.2, 10.4)], 0.35, 0.22, "folha_escura", lados=8, raiz=1.6)
    partes = [caule]
    for (z, lado, rot) in ((2.6, 1, 0), (4.8, -1, 140), (7.0, 1, 250)):
        r = math.radians(rot)
        partes.append(gc.copa("folha", 1.1, (math.cos(r) * 1.2 + 0.3, math.sin(r) * 1.2, z), "folha_media", int(z * 10),
                              escala=(1.4, 0.7, 0.25), sub=2))
    # flor inclinada para a frente, com miolo de "sementes" e pétalas em dois anéis
    cx, cy, cz = 1.5, -0.6, 10.8
    partes.append(k.cilindro("miolo", 1.6, 0.5, (cx, cy, cz), "madeira_escura", lados=16, rot=(70, 0, 15)))
    partes.append(k.cilindro("miolo_borda", 1.75, 0.35, (cx + 0.05, cy + 0.15, cz - 0.05), "couro", lados=16, rot=(70, 0, 15)))
    for anel, (dist, n, cor) in enumerate(((2.25, 14, "amarelo_sol"), (2.0, 14, "laranja"))):
        for i in range(n):
            a = (i + 0.5 * anel) * 360 / n
            ra = math.radians(a)
            # no plano da flor (girado 70° em X e 15° em Z)
            px, pz = math.cos(ra) * dist, math.sin(ra) * dist
            v = _girar(px, 0.0, pz, 70 - 90, 15)
            partes.append(k.esfera("petala", 0.6, (cx + v[0], cy + v[1] + 0.05 * anel, cz + v[2]), cor,
                                   escala=(0.55, 0.18, 1.0), segmentos=8, aneis=5, rot=(-20, -a + 90, 15)))
    o = k.unir(partes, "girassol_gigante_01")
    o["visibilidade_m"] = 600.0
    k.colisao_caixa("girassol_gigante_01", (0.8, 0.8, 8.0), (0.3, 0, 4.0))


def _girar(x, y, z, rx, rz):
    rx, rz = math.radians(rx), math.radians(rz)
    y, z = y * math.cos(rx) - z * math.sin(rx), y * math.sin(rx) + z * math.cos(rx)
    x, y = x * math.cos(rz) - y * math.sin(rz), x * math.sin(rz) + y * math.cos(rz)
    return (x, y, z)


def cogumelos_gigantes_01():
    partes = []
    for i, (x, y, h, r, cor) in enumerate(((0, 0, 5.2, 3.0, "vermelho"), (4.2, 1.6, 3.2, 1.9, "coral"), (-2.8, 3.4, 2.2, 1.4, "laranja"))):
        partes.append(gc.tronco("pe", [(x, y, 0), (x + 0.2, y, h * 0.5), (x - 0.15 * (i - 1), y + 0.1, h)], r * 0.28, r * 0.22, "areia", lados=10, raiz=1.4))
        chapeu = gc.copa("chapeu", r, (x, y, h), cor, 90 + i, escala=(1.0, 1.0, 0.5), achatar=0.15, ondas=0.06)
        partes.append(chapeu)
        for j in range(6):
            a = j * math.tau / 6 + i
            el = 0.55 + 0.25 * (j % 2)
            partes.append(k.esfera("pinta", r * 0.16, (x + math.cos(a) * r * 0.72 * math.cos(el), y + math.sin(a) * r * 0.72 * math.cos(el),
                                                     h + r * 0.5 * math.sin(el) + 0.05), "branco", escala=(1, 1, 0.45), segmentos=8, aneis=4))
    o = k.unir(partes, "cogumelos_gigantes_01")
    o["visibilidade_m"] = 500.0
    # pés sólidos; os chapéus são plataformas (dá para subir neles com construção/salto)
    k.colisao_caixa("cogumelos_gigantes_01", (1.6, 1.6, 5.0), (0, 0, 2.5))
    k.colisao_caixa("cogumelos_gigantes_01", (5.0, 5.0, 0.6), (0, 0, 5.4), sufixo="_2")
    k.colisao_caixa("cogumelos_gigantes_01", (1.0, 1.0, 3.0), (4.2, 1.6, 1.5), sufixo="_3")
    k.colisao_caixa("cogumelos_gigantes_01", (3.0, 3.0, 0.5), (4.2, 1.6, 3.4), sufixo="_4")
    k.colisao_caixa("cogumelos_gigantes_01", (0.8, 0.8, 2.0), (-2.8, 3.4, 1.0), sufixo="_5")
    k.colisao_caixa("cogumelos_gigantes_01", (2.2, 2.2, 0.4), (-2.8, 3.4, 2.35), sufixo="_6")


def pedras_equilibradas_01():
    pilha = [((0, 0, 1.2), 2.0, (1.3, 1.1, 0.75), "pedra_media"),
             ((0.6, 0.2, 3.1), 1.4, (1.2, 1.0, 0.8), "pedra_clara"),
             ((-0.3, -0.1, 4.75), 1.1, (1.5, 1.2, 0.6), "pedra_escura"),
             ((0.5, 0.3, 6.1), 0.85, (1.0, 0.9, 0.95), "pedra_media"),
             ((0.1, 0.1, 7.35), 0.6, (1.3, 1.1, 0.7), "pedra_clara")]
    partes = [gc.rocha(f"p{i}", r, pos, cor, 200 + i, escala=esc, forca=0.22) for i, (pos, r, esc, cor) in enumerate(pilha)]
    partes.append(gc.copa("musgo", 0.6, (0.4, 0.1, 7.75), "folha_media", 210, escala=(1.2, 1.0, 0.4), sub=2))
    partes.append(gc.copa("musgo2", 0.9, (-1.2, 0.6, 1.95), "folha_escura", 211, escala=(1.3, 1.0, 0.35), sub=2))
    o = k.unir(partes, "pedras_equilibradas_01")
    o["coleta"] = "pedra"
    o["visibilidade_m"] = 600.0
    k.colisao_caixa("pedras_equilibradas_01", (4.4, 3.6, 2.4), (0, 0, 1.2))
    k.colisao_caixa("pedras_equilibradas_01", (2.2, 2.0, 5.6), (0.3, 0.1, 5.0), sufixo="_2")


GERADORES = {f.__name__: f for f in (cata_vento_gigante_01, cata_vento_helice_01, farol_torto_01, girassol_gigante_01,
                                     cogumelos_gigantes_01, pedras_equilibradas_01)}


def main():
    for asset_id in sys.argv[1:] or list(GERADORES):
        k.nova_cena()
        GERADORES[asset_id]()
        k.salvar("cenario", asset_id)


if __name__ == "__main__":
    main()
