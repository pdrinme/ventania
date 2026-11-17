"""Gera a ambientação da Ilha Ventania (revisão da Etapa 4) e o Ônibus de Batalha.
Designs originais do projeto, no estilo do kit (blocos arredondados, paleta única).
Origem no chão (centro da base). Frente do objeto = -Y no Blender (+Z na Godot).

  poste_01       poste de rua com luminária
  banco_01       banco de praça
  lixeira_01     lixeira
  cerca_01       cerca de madeira (4 m, encaixa na grade)
  placa_01       placa de sinalização
  conteiner_01..03  contêiner de carga (coral, teal, amarelo)
  tronco_01      tronco caído
  girassol_01    girassol (decoração, sem colisão)
  silo_01        silo da fazenda
  carrinho_01    carrinho de mina com pedras
  tenda_01       barraca do acampamento
  onibus_01      Ônibus dos Ventos (ônibus voador com turbinas e leme de cata-vento)
  planador_01    planador de descida (asa delta)

Uso: python tools/assets/kit/blender/gerar_ambiente.py [id ...]
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kit_comum as k  # noqa: E402


def poste_01():
    p = [
        k.cilindro("base", 0.18, 0.3, (0, 0, 0.15), "metal_escuro", lados=8),
        k.cilindro("haste", 0.07, 4.2, (0, 0, 2.3), "metal_escuro", lados=8),
        k.caixa("braco", (0.08, 0.9, 0.08), (0, -0.4, 4.3), "metal_escuro"),
        k.caixa("luminaria", (0.34, 0.5, 0.18), (0, -0.85, 4.2), "metal_claro", bevel=0.04),
        k.caixa("lampada", (0.26, 0.4, 0.06), (0, -0.85, 4.1), "amarelo_sol"),
    ]
    k.unir(p, "poste_01")
    k.colisao_caixa("poste_01", (0.3, 0.3, 4.4), (0, 0, 2.2))


def banco_01():
    p = [k.caixa(f"tabua{i}", (1.8, 0.14, 0.06), (0, -0.2 + i * 0.16, 0.48), "madeira_media", bevel=0.015) for i in range(3)]
    p += [k.caixa(f"encosto{i}", (1.8, 0.05, 0.12), (0, 0.24, 0.72 + i * 0.16), "madeira_media", bevel=0.015) for i in range(2)]
    for x in (-0.75, 0.75):
        p.append(k.caixa(f"pe{x}", (0.08, 0.5, 0.46), (x, 0.0, 0.23), "metal_escuro"))
        p.append(k.caixa(f"apoio{x}", (0.08, 0.06, 0.5), (x, 0.24, 0.72), "metal_escuro"))
    k.unir(p, "banco_01")
    k.colisao_caixa("banco_01", (1.8, 0.55, 0.6), (0, 0, 0.3))


def lixeira_01():
    p = [
        k.cilindro("corpo", 0.3, 0.85, (0, 0, 0.43), "teal", lados=10),
        k.cilindro("tampa", 0.34, 0.1, (0, 0, 0.9), "teal_escuro", lados=10),
        k.toro("faixa", 0.305, 0.025, (0, 0, 0.55), "amarelo_sol", seg=10, seg_menor=4),
    ]
    k.unir(p, "lixeira_01")
    k.colisao_caixa("lixeira_01", (0.6, 0.6, 0.95), (0, 0, 0.47))


def cerca_01():
    p = [k.caixa(f"poste{x}", (0.14, 0.14, 1.2), (x, 0, 0.6), "madeira_escura", bevel=0.02) for x in (-1.9, 0.0, 1.9)]
    p += [k.caixa(f"trilho{z}", (4.0, 0.08, 0.14), (0, 0, z), "madeira_clara", bevel=0.02) for z in (0.45, 0.9)]
    k.unir(p, "cerca_01")
    k.colisao_caixa("cerca_01", (4.0, 0.2, 1.1), (0, 0, 0.55))


def placa_01():
    p = [
        k.cilindro("haste", 0.05, 2.2, (0, 0, 1.1), "metal_claro", lados=6),
        k.caixa("placa", (1.2, 0.06, 0.55), (0, -0.04, 2.0), "teal", bevel=0.04),
        k.caixa("seta", (0.7, 0.07, 0.14), (0.1, -0.06, 2.0), "branco"),
        k.cilindro("ponta", 0.12, 0.07, (0.48, -0.06, 2.0), "branco", lados=3, rot=(90, 0, 0)),
    ]
    k.unir(p, "placa_01")
    k.colisao_caixa("placa_01", (0.15, 0.15, 2.2), (0, 0, 1.1))


def _conteiner(asset_id, cor):
    p = [k.caixa("corpo", (6.0, 2.4, 2.6), (0, 0, 1.3), cor, bevel=0.05)]
    for i in range(9):
        x = -2.6 + i * 0.65
        p.append(k.caixa(f"nervura{i}", (0.12, 2.48, 2.3), (x, 0, 1.3), cor))
    p.append(k.caixa("portas", (0.06, 2.2, 2.4), (3.02, 0, 1.3), "metal_escuro"))
    p.append(k.caixa("trinco", (0.08, 0.1, 2.0), (3.06, 0.3, 1.3), "metal_claro"))
    k.unir(p, asset_id)
    k.colisao_caixa(asset_id, (6.0, 2.4, 2.6), (0, 0, 1.3))


def conteiner_01():
    _conteiner("conteiner_01", "coral")


def conteiner_02():
    _conteiner("conteiner_02", "teal")


def conteiner_03():
    _conteiner("conteiner_03", "amarelo_sol")


def tronco_01():
    p = [
        k.cilindro("tora", 0.35, 2.6, (0, 0, 0.33), "tronco", lados=8, rot=(0, 90, 0)),
        k.cilindro("anel1", 0.3, 0.02, (1.31, 0, 0.33), "madeira_clara", lados=8, rot=(0, 90, 0)),
        k.cilindro("anel2", 0.3, 0.02, (-1.31, 0, 0.33), "madeira_clara", lados=8, rot=(0, 90, 0)),
        k.cilindro("galho", 0.08, 0.6, (0.4, 0.25, 0.5), "tronco", lados=5, rot=(-50, 0, 0), raio_topo=0.03),
    ]
    k.unir(p, "tronco_01")
    k.colisao_caixa("tronco_01", (2.6, 0.7, 0.66), (0, 0, 0.33))


def girassol_01():
    p = [
        k.cilindro("caule", 0.03, 1.5, (0, 0, 0.75), "folha_media", lados=5),
        k.caixa("folha1", (0.32, 0.04, 0.14), (0.16, 0, 0.7), "folha_clara", rot=(0, -25, 0)),
        k.caixa("folha2", (0.3, 0.04, 0.13), (-0.15, 0, 0.95), "folha_clara", rot=(0, 25, 0)),
        k.cilindro("petalas", 0.24, 0.05, (0, -0.03, 1.55), "amarelo_sol", lados=10, rot=(80, 0, 0)),
        k.cilindro("miolo", 0.12, 0.07, (0, -0.06, 1.55), "madeira_escura", lados=8, rot=(80, 0, 0)),
    ]
    k.unir(p, "girassol_01")   # sem colisão: plantação para atravessar e se esconder


def silo_01():
    p = [
        k.cilindro("corpo", 2.3, 8.0, (0, 0, 4.0), "metal_claro", lados=14),
        k.esfera("cupula", 2.3, (0, 0, 8.0), "coral", escala=(1, 1, 0.55), segmentos=14, aneis=6),
        k.toro("anel1", 2.32, 0.06, (0, 0, 2.5), "metal_escuro", seg=14, seg_menor=4),
        k.toro("anel2", 2.32, 0.06, (0, 0, 5.5), "metal_escuro", seg=14, seg_menor=4),
        k.caixa("escada", (0.4, 0.1, 8.0), (0, -2.35, 4.0), "metal_escuro"),
    ]
    k.unir(p, "silo_01")
    k.colisao_convexa("silo_01", [(2.3 * math.cos(a * math.pi / 6), 2.3 * math.sin(a * math.pi / 6), z)
                                  for a in range(12) for z in (0.0, 9.2)])


def carrinho_01():
    p = [
        k.caixa("caixa", (1.4, 0.9, 0.7), (0, 0, 0.7), "metal_escuro", bevel=0.04),
        k.caixa("borda", (1.5, 1.0, 0.08), (0, 0, 1.05), "laranja"),
        k.icoesfera("pedras1", 0.38, (0.25, 0, 1.1), "pedra_clara", ruido=0.2, semente=11),
        k.icoesfera("pedras2", 0.32, (-0.3, 0.1, 1.08), "pedra_media", ruido=0.2, semente=12),
    ]
    for x in (-0.5, 0.5):
        for y in (-0.45, 0.45):
            p.append(k.cilindro(f"roda{x}{y}", 0.2, 0.1, (x, y, 0.22), "preto", lados=8, rot=(90, 0, 0)))
    p.append(k.caixa("trilho1", (4.0, 0.08, 0.06), (0, -0.45, 0.03), "metal_claro"))
    p.append(k.caixa("trilho2", (4.0, 0.08, 0.06), (0, 0.45, 0.03), "metal_claro"))
    k.unir(p, "carrinho_01")
    k.colisao_caixa("carrinho_01", (1.5, 1.0, 1.2), (0, 0, 0.6))


def tenda_01():
    lados = []
    for s in (-1, 1):
        lados.append(k.caixa(f"lona{s}", (2.6, 0.05, 1.7), (0, s * 0.6, 0.72), "coral", rot=(s * 45, 0, 0)))
    p = lados + [
        k.caixa("cume", (2.7, 0.12, 0.12), (0, 0, 1.3), "madeira_escura"),
        k.caixa("chao", (2.6, 2.4, 0.04), (0, 0, 0.02), "teal_escuro"),
    ]
    k.unir(p, "tenda_01")
    k.colisao_convexa("tenda_01", [(x, y, z) for x in (-1.3, 1.3) for (y, z) in ((-1.2, 0), (1.2, 0), (0, 1.35))])


def onibus_01():
    """Ônibus dos Ventos: carroceria teal com faixas amarelas, janelas, duas turbinas
    laterais com hélices e um leme de cata-vento no teto. ~9 m de comprimento."""
    p = [
        k.caixa("carroceria", (2.8, 9.0, 2.7), (0, 0, 2.0), "teal", bevel=0.35),
        k.caixa("teto", (2.5, 8.2, 0.3), (0, 0, 3.45), "teal_escuro", bevel=0.12),
        k.caixa("faixa", (2.84, 9.04, 0.35), (0, 0, 1.55), "amarelo_sol", bevel=0.1),
        k.caixa("para_brisa", (2.3, 0.1, 1.0), (0, -4.52, 2.55), "lente"),
        k.caixa("para_choque", (2.6, 0.3, 0.35), (0, -4.6, 0.8), "metal_escuro", bevel=0.08),
    ]
    for i in range(5):
        y = -2.8 + i * 1.4
        for s in (-1, 1):
            p.append(k.caixa(f"janela{i}{s}", (0.06, 1.0, 0.8), (s * 1.41, y, 2.55), "lente"))
    for s in (-1, 1):
        p.append(k.cilindro(f"roda_d{s}", 0.55, 0.4, (s * 1.25, -2.8, 0.55), "preto", lados=10, rot=(0, 90, 0)))
        p.append(k.cilindro(f"roda_t{s}", 0.55, 0.4, (s * 1.25, 2.8, 0.55), "preto", lados=10, rot=(0, 90, 0)))
        p.append(k.cilindro(f"turbina{s}", 0.75, 2.2, (s * 2.25, 0.3, 2.3), "metal_claro", lados=12, rot=(90, 0, 0)))
        p.append(k.toro(f"bocal{s}", 0.75, 0.12, (s * 2.25, -0.8, 2.3), "coral", rot=(90, 0, 0), seg=12, seg_menor=4))
        p.append(k.caixa(f"helice{s}", (1.3, 0.06, 0.18), (s * 2.25, -0.86, 2.3), "metal_escuro", rot=(0, 30, 0)))
        p.append(k.caixa(f"suporte{s}", (0.7, 0.4, 0.2), (s * 1.65, 0.3, 2.3), "metal_escuro"))
    # porta traseira aberta (de onde se salta): vão escuro, batente amarelo e degrau
    p.append(k.caixa("vao_porta", (1.3, 0.06, 2.0), (0, 4.52, 1.75), "preto"))
    p.append(k.caixa("batente_e", (0.14, 0.14, 2.2), (0.72, 4.55, 1.8), "amarelo_sol"))
    p.append(k.caixa("batente_d", (0.14, 0.14, 2.2), (-0.72, 4.55, 1.8), "amarelo_sol"))
    p.append(k.caixa("batente_topo", (1.58, 0.14, 0.14), (0, 4.55, 2.86), "amarelo_sol"))
    p.append(k.caixa("degrau", (1.4, 0.5, 0.12), (0, 4.75, 0.72), "metal_escuro"))
    # leme de cata-vento (identidade do Ventania)
    p.append(k.cilindro("mastro", 0.08, 1.4, (0, 2.8, 4.3), "metal_escuro", lados=6))
    for a in range(4):
        p.append(k.caixa(f"pa{a}", (0.08, 0.9, 0.45), (0, 2.8, 4.9), ["coral", "amarelo_sol", "teal", "roxo"][a],
                         rot=(a * 90, 0, 0)))
    k.unir(p, "onibus_01")


def planador_01():
    """Planador de descida: asa delta teal com borda amarela e barra de apoio."""
    import bpy
    malha = bpy.data.meshes.new("asa")
    verts = [(0, -1.4, 0.15), (2.4, 0.9, 0.0), (0, 0.4, 0.1), (-2.4, 0.9, 0.0)]
    malha.from_pydata(verts, [], [(0, 1, 2), (0, 2, 3)])
    asa = bpy.data.objects.new("asa", malha)
    bpy.context.scene.collection.objects.link(asa)
    bpy.context.view_layer.objects.active = asa
    asa.select_set(True)
    mod = asa.modifiers.new("espessura", "SOLIDIFY")
    mod.thickness = 0.06
    bpy.ops.object.modifier_apply(modifier=mod.name)
    k.pintar(asa, "teal")
    p = [
        asa,
        k.caixa("borda_e", (0.12, 3.3, 0.08), (1.2, -0.25, 0.08), "amarelo_sol", rot=(0, 0, -46)),
        k.caixa("borda_d", (0.12, 3.3, 0.08), (-1.2, -0.25, 0.08), "amarelo_sol", rot=(0, 0, 46)),
        k.cilindro("mastro", 0.03, 1.1, (0, -0.2, -0.5), "metal_escuro", lados=6),
        k.caixa("barra", (1.0, 0.06, 0.06), (0, -0.2, -1.05), "metal_escuro"),
    ]
    k.unir(p, "planador_01")


GERADORES = {f.__name__: f for f in (poste_01, banco_01, lixeira_01, cerca_01, placa_01, conteiner_01, conteiner_02,
                                     conteiner_03, tronco_01, girassol_01, silo_01, carrinho_01, tenda_01, onibus_01,
                                     planador_01)}


def main():
    for asset_id in sys.argv[1:] or list(GERADORES):
        k.nova_cena()
        GERADORES[asset_id]()
        k.salvar("cenario", asset_id)


if __name__ == "__main__":
    main()
