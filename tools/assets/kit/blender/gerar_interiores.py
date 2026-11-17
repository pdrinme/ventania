"""Interiores das construções do mapa: escadas reais (com degraus) e mobília.

Uso: python tools/assets/kit/blender/gerar_interiores.py [id ...]

Coordenadas: as funções recebem posições no padrão da GODOT (x, y para cima, z),
com a origem no CENTRO do cômodo de 4 × 4 m e no nível do piso de baixo (topo do
piso de construção = y 0,1). A conversão para o Blender (Z para cima, frente -Y)
é feita aqui: Blender (x, -z, y).

ESCADA EM "U" (um cômodo, de um andar ao seguinte, 4 m):
  - lance 1 na faixa z 0,05..1,95, subindo de x = +2 (porta para o cômodo vizinho
    +x) até o patamar em x ≈ -0,6; 9 degraus de 0,27 m (piso) por 0,2 m (espelho);
  - patamar (y 2,1) junto à parede x = -2;
  - lance 2 na faixa z -1,95..-0,05, voltando até x = +2 no andar de cima (y 4,1),
    onde chega no piso do cômodo vizinho;
  - parede central entre os lances, guarda-corpo do lado aberto do lance 2 e do
    patamar, e guarda-corpos no andar de cima em volta do vão da escada.
COLISÃO: cada lance é um prisma cujo plano passa pelo MEIO DE CADA PISO dos
degraus (o pé fica na altura do degrau, sem trancos nem degraus de 20 cm para o
controlador subir). Patamar, parede central e guarda-corpos são sólidos.
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kit_comum as k  # noqa: E402
import bpy  # noqa: E402

PISO = 0.1            # topo do piso de construção
ANDAR = 4.0
ESPELHO = 0.2
PISADA = 0.27
X_PATAMAR = -0.665    # onde a colisão dos lances encontra o patamar
ESP_LAJE = 0.25       # espessura da laje do lance 2


def B(p):
    """Godot (x, y, z) -> Blender (x, -z, y)."""
    return (p[0], -p[2], p[1])


def gcaixa(nome, tam, pos, cor, bevel=0.0):
    """Caixa em coordenadas da Godot: tam = (x, y, z)."""
    return k.caixa(nome, (tam[0], tam[2], tam[1]), B(pos), cor, bevel=bevel)


def prisma(nome, perfil, z0, z1, cor=None, colisao=False):
    """Polígono CONVEXO no plano x-y (Godot) extrudado de z0 a z1. Visual (cor)
    ou colisão (-convcolonly)."""
    vs = [B((x, y, z0)) for x, y in perfil] + [B((x, y, z1)) for x, y in perfil]
    if colisao:
        return k.colisao_convexa(nome, vs)
    n = len(perfil)
    faces = [list(range(n))[::-1], [i + n for i in range(n)]]
    for i in range(n):
        j = (i + 1) % n
        faces.append([i, j, j + n, i + n])
    malha = bpy.data.meshes.new(nome)
    malha.from_pydata(vs, [], faces)
    malha.update()
    o = bpy.data.objects.new(nome, malha)
    bpy.context.scene.collection.objects.link(o)
    k._ativo(o)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    return k.pintar(o, cor)


# ------------------------------------------------------------------ escadas

def _perfil_lance1():
    # sobe para -x: (2, 0,1) -> (X_PATAMAR, 2,1), sólido até o piso
    return [(2.0, PISO), (X_PATAMAR, PISO + 2.0), (X_PATAMAR, PISO)]


def _perfil_lance2():
    # sobe para +x: (X_PATAMAR, 2,1) -> (2, 4,1)
    return [(X_PATAMAR, PISO), (X_PATAMAR, PISO + 2.0), (2.0, PISO + ANDAR), (2.0, PISO)]


def _colisoes(asset_id):
    # faixa do lance 1 + patamar numa forma convexa só (sem quina entre corpos no topo
    # do lance, onde o personagem andando devagar enroscava)
    prisma(f"{asset_id}_lance1", [(2.0, PISO), (X_PATAMAR, PISO + 2.0), (-1.95, PISO + 2.0), (-1.95, PISO)], -0.05, 1.95, colisao=True)
    # patamar do lado do lance 2
    larg = X_PATAMAR + 1.95
    k.colisao_caixa(asset_id, (larg, 1.9, 2.0), B((-1.95 + larg / 2, PISO + 1.0, -1.0)), sufixo="_patamar")
    # lance 2 com uma aba plana de 0,3 m no topo, no nível do piso de cima (o mesmo
    # motivo: o topo da subida fica dentro de uma forma só)
    # O lance 2 é uma LAJE inclinada (0,25 m), com vão livre por baixo: nos prédios
    # com escadas empilhadas, quem sobe o lance 2 de baixo passa sob o lance 2 de cima.
    prisma(f"{asset_id}_lance2", [(X_PATAMAR, PISO + 2.0 - ESP_LAJE), (X_PATAMAR, PISO + 2.0), (2.0, PISO + ANDAR), (2.3, PISO + ANDAR),
                                  (2.3, PISO + ANDAR - ESP_LAJE), (2.0, PISO + ANDAR - ESP_LAJE)], -1.95, -0.05, colisao=True)
    # parede central (z = 0), topo inclinado a 1 m acima do lance 2
    prisma(f"{asset_id}_central", [(X_PATAMAR, PISO), (X_PATAMAR, PISO + 3.0), (2.0, PISO + ANDAR + 1.0), (2.0, PISO)], -0.06, 0.06, colisao=True)
    # guarda-corpo do lado aberto do lance 2 e do patamar (z = -1,95)
    prisma(f"{asset_id}_gc_lance", [(X_PATAMAR, PISO + 2.0), (X_PATAMAR, PISO + 3.0), (2.0, PISO + ANDAR + 1.0), (2.0, PISO + ANDAR)], -1.98, -1.90, colisao=True)
    k.colisao_caixa(asset_id, (larg, 0.08, 1.0), B((-1.95 + larg / 2, PISO + 2.5, -1.94)), sufixo="_gc_patamar")


def _colisoes_topo(asset_id):
    """Andar de cima do último lance: guarda-corpos em volta do vão (borda x = +2 sobre
    o lance 1 e borda z = -2). Asset separado: nos prédios com escadas empilhadas, o
    vão do meio é a entrada do lance seguinte e não pode ter guarda-corpo."""
    k.colisao_caixa(asset_id, (0.08, 1.9, 1.0), B((1.96, PISO + ANDAR + 0.5, 1.0)), sufixo="_gc_cima_x")
    k.colisao_caixa(asset_id, (4.0, 0.08, 1.0), B((0.0, PISO + ANDAR + 0.5, -1.98)), sufixo="_gc_cima_z")


def _degraus(cores, aberta=False, focinho=0.03):
    """9 degraus por lance. aberta: só a chapa do piso (sem espelho), para a escada de metal."""
    pecas = []
    for i in range(9):
        topo = PISO + ESPELHO * (i + 1)
        # lance 1: piso entre x = 2 - 0,27 (i+1) e 2 - 0,27 i (sobe para -x)
        x1 = 2.0 - PISADA * (i + 0.5)
        x2 = -0.53 + PISADA * (i + 0.5)
        topo2 = PISO + 2.0 + ESPELHO * (i + 1)
        for x, t, z, sinal in ((x1, topo, 1.0, -1), (x2, topo2, -1.0, 1)):
            esp = 0.05 if aberta else ESPELHO + 0.02
            pecas.append(gcaixa(f"piso_{i}_{z}", (PISADA + focinho, esp, 1.88), (x + sinal * focinho / 2, t - esp / 2, z),
                                cores["piso"], bevel=0.01))
            if not aberta:
                # espelho em outro tom (lê como degrau mesmo de longe)
                pecas.append(gcaixa(f"esp_{i}_{z}", (0.02, ESPELHO, 1.86), (x - sinal * PISADA / 2 + sinal * 0.012, t - ESPELHO / 2, z), cores["espelho"]))
            if cores.get("focinho"):
                pecas.append(gcaixa(f"foc_{i}_{z}", (0.05, 0.012, 1.88), (x + sinal * (PISADA / 2 + focinho - 0.025), t + 0.004, z), cores["focinho"]))
    return pecas


def _corpo(cores):
    """Laterais/estrutura sólida sob os lances, patamar e parede central (visual da colisão)."""
    pecas = [
        prisma("lado1", [(2.0, PISO), (X_PATAMAR, PISO + 2.0 - 0.21), (X_PATAMAR, PISO)], 0.06, 1.94, cores["corpo"]),
        # lance 2: laje inclinada (vão livre embaixo)
        prisma("lado2", [(X_PATAMAR, PISO + 2.0 - ESP_LAJE), (X_PATAMAR, PISO + 2.0 - 0.18), (2.0, PISO + ANDAR - 0.18), (2.0, PISO + ANDAR - ESP_LAJE)],
               -1.94, -0.06, cores["corpo"]),
    ]
    larg = X_PATAMAR + 1.95 + 0.135
    pecas.append(gcaixa("patamar", (larg, 2.0, 3.9), (-1.95 + larg / 2, PISO + 1.0, 0), cores["patamar_base"]))
    pecas.append(gcaixa("patamar_topo", (larg + 0.02, 0.06, 3.92), (-1.95 + larg / 2, PISO + 2.0 - 0.03, 0), cores["piso"]))
    pecas.append(prisma("central", [(X_PATAMAR + 0.13, PISO), (X_PATAMAR + 0.13, PISO + 3.0), (2.0, PISO + ANDAR + 1.0), (2.0, PISO)], -0.06, 0.06, cores["central"]))
    return pecas


def _corrimao(cores, balaustres, tubo=False):
    """Corrimão do lado aberto do lance 2 + patamar e guarda-corpos do andar de cima."""
    pecas = []
    r = cores["corrimao"]
    # lance 2: corrimão inclinado em z = -1,94
    comp = math.hypot(2.0 - X_PATAMAR, ANDAR - 2.0)
    ang = math.degrees(math.atan2(ANDAR - 2.0, 2.0 - X_PATAMAR))
    meio = ((2.0 + X_PATAMAR) / 2, PISO + 3.0 + 1.0 - 0.04, -1.94)
    o = gcaixa("corrimao_lance", (comp, 0.07, 0.08), meio, r, bevel=0.015)
    o.rotation_euler = (0, -math.radians(ang), 0)   # gira no plano x-y da Godot (eixo Y do Blender)
    k._aplicar(o)
    pecas.append(o)
    # balaústres (madeira) ou montantes (metal/concreto)
    passos = 7 if balaustres else 3
    for i in range(passos + 1):
        f = i / passos
        x = X_PATAMAR + f * (2.0 - X_PATAMAR)
        base = PISO + 2.0 + f * 2.0
        pecas.append(gcaixa(f"bal_{i}", (0.05, 1.0, 0.05), (x, base + 0.5, -1.94), cores["balaustre"]))
    # patamar e andar de cima
    larg = X_PATAMAR + 1.95
    pecas.append(gcaixa("corr_patamar", (larg, 0.07, 0.08), (-1.95 + larg / 2, PISO + 3.0 - 0.04, -1.94), r, bevel=0.015))
    pecas.append(gcaixa("bal_patamar", (0.05, 1.0, 0.05), (-1.9, PISO + 2.5, -1.94), cores["balaustre"]))
    return pecas


def _corrimao_topo(cores, balaustres, tubo):
    pecas = []
    r = cores["corrimao"]
    pecas.append(gcaixa("corr_cima_x", (0.08, 0.07, 1.95), (1.96, PISO + ANDAR + 1.0 - 0.04, 1.0), r, bevel=0.015))
    pecas.append(gcaixa("corr_cima_z", (4.0, 0.07, 0.08), (0.0, PISO + ANDAR + 1.0 - 0.04, -1.98), r, bevel=0.015))
    n_cima = 5 if balaustres else 3
    for i in range(n_cima):
        pecas.append(gcaixa(f"bal_cx_{i}", (0.05, 1.0, 0.05), (1.96, PISO + ANDAR + 0.5, 0.1 + i * 1.8 / (n_cima - 1)), cores["balaustre"]))
    for i in range(n_cima * 2 - 1):
        pecas.append(gcaixa(f"bal_cz_{i}", (0.05, 1.0, 0.05), (-1.9 + i * 3.8 / (n_cima * 2 - 2), PISO + ANDAR + 0.5, -1.98), cores["balaustre"]))
    if tubo:
        # tela/chapa baixa entre os montantes (metal): rodapé do guarda-corpo
        pecas.append(gcaixa("rodape_cz", (4.0, 0.12, 0.03), (0.0, PISO + ANDAR + 0.06, -1.98), cores["corrimao"]))
        pecas.append(gcaixa("rodape_cx", (0.03, 0.12, 1.95), (1.96, PISO + ANDAR + 0.06, 1.0), cores["corrimao"]))
    return pecas


def _escada(asset_id, cores, balaustres, aberta, tubo):
    pecas = _degraus(cores, aberta=aberta) + _corpo(cores) + _corrimao(cores, balaustres, tubo)
    o = k.unir(pecas, asset_id)
    o["visibilidade_m"] = 90.0
    _colisoes(asset_id)
    # pontos de passagem para a navegação (documentação; a Godot usa os mesmos números)
    k.marcador("nav_entrada", B((2.6, PISO, 1.0)))
    k.marcador("nav_saida", B((2.6, PISO + ANDAR, -1.0)))
    # guarda-corpo do vão no andar de cima (só no último lance)
    bpy.ops.object.select_all(action="DESELECT")


def _topo(asset_id, cores, balaustres, tubo):
    o = k.unir(_corrimao_topo(cores, balaustres, tubo), asset_id)
    o["visibilidade_m"] = 90.0
    _colisoes_topo(asset_id)


MADEIRA = {"piso": "madeira_clara", "espelho": "madeira_escura", "corpo": "madeira_media", "patamar_base": "madeira_media",
           "central": "madeira_media", "corrimao": "madeira_escura", "balaustre": "madeira_clara"}
CONCRETO = {"piso": "pedra_clara", "espelho": "pedra_media", "corpo": "pedra_media", "patamar_base": "pedra_media",
            "central": "pedra_clara", "focinho": "pedra_escura", "corrimao": "metal_escuro", "balaustre": "metal_claro"}
METAL = {"piso": "metal_claro", "espelho": "metal_escuro", "corpo": "metal_escuro", "patamar_base": "metal_escuro",
         "central": "metal_claro", "focinho": "amarelo_sol", "corrimao": "amarelo_sol", "balaustre": "metal_escuro"}


def escada_madeira_01():
    """Casas: degraus de madeira clara com espelho escuro, balaústres e corrimão de madeira."""
    _escada("escada_madeira_01", MADEIRA, balaustres=True, aberta=False, tubo=False)


def escada_madeira_topo_01():
    _topo("escada_madeira_topo_01", MADEIRA, balaustres=True, tubo=False)


def escada_concreto_topo_01():
    _topo("escada_concreto_topo_01", CONCRETO, balaustres=False, tubo=False)


def escada_metal_topo_01():
    _topo("escada_metal_topo_01", METAL, balaustres=False, tubo=True)


def escada_concreto_01():
    """Lojas e prédios: degraus de concreto, faixa de borda escura, corrimão de metal."""
    _escada("escada_concreto_01", CONCRETO, balaustres=False, aberta=False, tubo=False)


def escada_metal_01():
    """Galpões: chapas de piso vazadas (sem espelho) com borda amarela, estrutura e guarda-corpo de metal."""
    _escada("escada_metal_01", METAL, balaustres=False, aberta=True, tubo=True)


GERADORES = {f.__name__: f for f in (escada_madeira_01, escada_concreto_01, escada_metal_01,
                                      escada_madeira_topo_01, escada_concreto_topo_01, escada_metal_topo_01)}


def main():
    for asset_id in sys.argv[1:] or list(GERADORES):
        k.nova_cena()
        GERADORES[asset_id]()
        k.salvar("cenario", asset_id)


if __name__ == "__main__":
    main()
