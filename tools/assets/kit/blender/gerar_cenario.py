"""Gera props de cenário estilizados: árvore redonda, pinheiro, pedra, arbusto.

Uso: python tools/assets/kit/blender/gerar_cenario.py [id ...]
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kit_comum as k  # noqa: E402


def arvore_redonda_01():
    tronco = k.cilindro("tronco", 0.32, 3.0, (0, 0, 1.5), "tronco", lados=8, raio_topo=0.2)
    galho = k.cilindro("galho", 0.12, 1.0, (0.35, 0, 2.4), "tronco", lados=6, rot=(0, 40, 0), raio_topo=0.06)
    copa = [
        k.icoesfera("copa1", 1.5, (0, 0, 3.7), "folha_media", escala=(1, 1, 0.85), ruido=0.12, semente=1),
        k.icoesfera("copa2", 1.05, (0.95, 0.3, 3.2), "folha_clara", escala=(1, 1, 0.85), ruido=0.12, semente=2),
        k.icoesfera("copa3", 0.95, (-0.8, -0.5, 3.35), "folha_escura", escala=(1, 1, 0.85), ruido=0.12, semente=3),
    ]
    o = k.unir([tronco, galho] + copa, "arvore_redonda_01")
    o["coleta"] = "madeira"
    o["visibilidade_m"] = 250.0
    k.colisao_caixa("arvore_redonda_01", (0.6, 0.6, 3.0), (0, 0, 1.5))


def pinheiro_01():
    tronco = k.cilindro("tronco", 0.25, 1.4, (0, 0, 0.7), "tronco", lados=6, raio_topo=0.18)
    camadas = []
    for i, (r, z, cor) in enumerate([(1.5, 1.9, "folha_escura"), (1.15, 3.0, "folha_media"), (0.8, 4.0, "folha_escura")]):
        camadas.append(k.cilindro(f"camada{i}", r, 1.6, (0, 0, z), cor, lados=7, raio_topo=0.12))
    o = k.unir([tronco] + camadas, "pinheiro_01")
    o["coleta"] = "madeira"
    o["visibilidade_m"] = 250.0
    k.colisao_caixa("pinheiro_01", (0.5, 0.5, 4.0), (0, 0, 2.0))


def pedra_01():
    grande = k.icoesfera("grande", 1.0, (0, 0, 0.55), "pedra_media", escala=(1.5, 1.15, 0.85), ruido=0.18, semente=4)
    pequena = k.icoesfera("pequena", 0.55, (1.15, -0.45, 0.3), "pedra_clara", escala=(1.2, 1, 0.8), ruido=0.2, semente=5)
    o = k.unir([grande, pequena], "pedra_01")
    o["coleta"] = "pedra"
    o["visibilidade_m"] = 200.0
    k.colisao_caixa("pedra_01", (2.6, 2.0, 1.2), (0.2, -0.1, 0.55))


def arbusto_01():
    partes = [
        k.icoesfera("b1", 0.6, (0, 0, 0.45), "folha_media", escala=(1, 1, 0.8), ruido=0.15, semente=6),
        k.icoesfera("b2", 0.45, (0.55, 0.15, 0.35), "folha_clara", escala=(1, 1, 0.8), ruido=0.15, semente=7),
        k.icoesfera("b3", 0.42, (-0.5, -0.2, 0.32), "folha_escura", escala=(1, 1, 0.8), ruido=0.15, semente=8),
    ]
    o = k.unir(partes, "arbusto_01")
    o["visibilidade_m"] = 120.0  # sem colisão: dá para se esconder dentro


GERADORES = {f.__name__: f for f in (arvore_redonda_01, pinheiro_01, pedra_01, arbusto_01)}


def main():
    for asset_id in sys.argv[1:] or list(GERADORES):
        k.nova_cena()
        GERADORES[asset_id]()
        k.salvar("cenario", asset_id)


if __name__ == "__main__":
    main()
