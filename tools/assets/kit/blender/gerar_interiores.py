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


# ------------------------------------------------------------------ mobília
# Convenção: origem no centro do móvel, no chão (y = 0); FRENTE para +z (Godot),
# costas em -z (encostadas na parede). Colisão: caixas simples (ou nenhuma, para
# peças pequenas que não devem prender ninguém: cadeira, luminária, tapete).
# Visível a até VIS_MOVEL m e sem sombra (dentro das casas a sombra já é da casa).

VIS_MOVEL = 40.0


def gcil(nome, raio, altura, pos, cor, lados=10):
    """Cilindro em pé (eixo Y da Godot), pos = centro."""
    return k.cilindro(nome, raio, altura, B(pos), cor, lados=lados)


def gcol(asset_id, sufixo, tam, pos):
    k.colisao_caixa(asset_id, (tam[0], tam[2], tam[1]), B(pos), sufixo=sufixo)


def _fechar(asset_id, pecas):
    o = k.unir(pecas, asset_id)
    o.name = asset_id + "-noshadow"
    o["visibilidade_m"] = VIS_MOVEL
    return o


def sofa_01():
    p = [gcaixa("base", (2.0, 0.42, 0.9), (0, 0.21, 0), "teal_escuro", 0.04),
         gcaixa("encosto", (2.0, 0.5, 0.22), (0, 0.66, -0.34), "teal_escuro", 0.05),
         gcaixa("braco_e", (0.2, 0.25, 0.9), (-0.9, 0.55, 0), "teal_escuro", 0.05),
         gcaixa("braco_d", (0.2, 0.25, 0.9), (0.9, 0.55, 0), "teal_escuro", 0.05)]
    for i in range(2):
        p.append(gcaixa(f"almofada{i}", (0.78, 0.14, 0.62), (-0.4 + i * 0.8, 0.49, 0.08), "teal", 0.05))
    p.append(gcaixa("almofada_solta", (0.36, 0.32, 0.12), (0.62, 0.66, -0.15), "coral", 0.05))
    _fechar("sofa_01", p)
    gcol("sofa_01", "", (2.0, 0.9, 0.9), (0, 0.45, 0))


def mesa_01():
    p = [gcaixa("tampo", (1.4, 0.06, 0.9), (0, 0.75, 0), "madeira_media", 0.02)]
    for sx in (-1, 1):
        for sz in (-1, 1):
            p.append(gcaixa(f"perna{sx}{sz}", (0.07, 0.72, 0.07), (sx * 0.62, 0.36, sz * 0.38), "madeira_escura"))
    p.append(gcaixa("toalha", (0.7, 0.01, 0.9), (0, 0.785, 0), "branco"))
    p.append(gcil("vaso", 0.07, 0.18, (0.35, 0.87, 0.1), "azul_ceu", 8))
    p.append(k.icoesfera("flor", 0.09, B((0.35, 1.0, 0.1)), "amarelo_sol"))
    _fechar("mesa_01", p)
    gcol("mesa_01", "", (1.4, 0.78, 0.9), (0, 0.39, 0))


def cadeira_01():
    p = [gcaixa("assento", (0.45, 0.05, 0.45), (0, 0.46, 0), "madeira_media", 0.01),
         gcaixa("encosto", (0.45, 0.45, 0.05), (0, 0.7, -0.2), "madeira_media", 0.01)]
    for sx in (-1, 1):
        for sz in (-1, 1):
            p.append(gcaixa(f"perna{sx}{sz}", (0.05, 0.45, 0.05), (sx * 0.19, 0.22, sz * 0.19), "madeira_escura"))
    _fechar("cadeira_01", p)          # sem colisão: não prende ninguém


def cama_01():
    """Cama de solteiro (1 × 2 m): cabe encostada na parede sem fechar o meio do cômodo."""
    p = [gcaixa("estrado", (1.0, 0.3, 2.0), (0, 0.2, 0), "madeira_escura", 0.03),
         gcaixa("colchao", (0.94, 0.2, 1.9), (0, 0.45, 0.03), "branco", 0.05),
         gcaixa("coberta", (0.98, 0.08, 1.3), (0, 0.56, 0.33), "azul_tormenta", 0.04),
         gcaixa("dobra", (0.98, 0.09, 0.18), (0, 0.6, -0.32), "branco", 0.03),
         gcaixa("cabeceira", (1.0, 1.0, 0.1), (0, 0.5, -0.98), "madeira_media", 0.03),
         gcaixa("travesseiro", (0.6, 0.12, 0.35), (0, 0.6, -0.7), "branco", 0.05)]
    _fechar("cama_01", p)
    gcol("cama_01", "", (1.0, 0.62, 2.0), (0, 0.31, 0))
    gcol("cama_01", "_cab", (1.0, 1.0, 0.12), (0, 0.5, -0.98))


def armario_01():
    p = [gcaixa("corpo", (1.2, 2.0, 0.6), (0, 1.0, 0), "madeira_escura", 0.03),
         gcaixa("porta_e", (0.57, 1.8, 0.02), (-0.295, 1.02, 0.305), "madeira_media"),
         gcaixa("porta_d", (0.57, 1.8, 0.02), (0.295, 1.02, 0.305), "madeira_media"),
         gcaixa("puxador_e", (0.03, 0.2, 0.03), (-0.05, 1.05, 0.33), "dourado"),
         gcaixa("puxador_d", (0.03, 0.2, 0.03), (0.05, 1.05, 0.33), "dourado")]
    _fechar("armario_01", p)
    gcol("armario_01", "", (1.2, 2.0, 0.6), (0, 1.0, 0))


def geladeira_01():
    p = [gcaixa("corpo", (0.75, 1.8, 0.7), (0, 0.9, 0), "branco", 0.05),
         gcaixa("divisao", (0.74, 0.02, 0.02), (0, 1.25, 0.355), "metal_claro"),
         gcaixa("puxador1", (0.04, 0.3, 0.04), (0.3, 1.45, 0.37), "metal_escuro"),
         gcaixa("puxador2", (0.04, 0.4, 0.04), (0.3, 0.85, 0.37), "metal_escuro"),
         gcaixa("ima", (0.1, 0.1, 0.01), (-0.15, 1.5, 0.355), "coral")]
    _fechar("geladeira_01", p)
    gcol("geladeira_01", "", (0.75, 1.8, 0.7), (0, 0.9, 0))


def fogao_01():
    p = [gcaixa("corpo", (0.75, 0.88, 0.65), (0, 0.44, 0), "branco", 0.03),
         gcaixa("forno", (0.6, 0.4, 0.02), (0, 0.4, 0.33), "preto"),
         gcaixa("painel", (0.75, 0.12, 0.06), (0, 0.95, -0.3), "metal_claro")]
    for i, (x, z) in enumerate(((-0.18, -0.12), (0.18, -0.12), (-0.18, 0.15), (0.18, 0.15))):
        p.append(gcil(f"boca{i}", 0.09, 0.02, (x, 0.89, z), "preto", 10))
    p.append(gcil("panela", 0.13, 0.16, (-0.18, 0.98, 0.15), "vermelho", 10))
    _fechar("fogao_01", p)
    gcol("fogao_01", "", (0.75, 0.95, 0.65), (0, 0.475, 0))


def pia_cozinha_01():
    p = [gcaixa("armario", (1.6, 0.86, 0.62), (0, 0.43, 0), "madeira_clara", 0.02),
         gcaixa("bancada", (1.64, 0.05, 0.66), (0, 0.885, 0), "pedra_clara", 0.01),
         gcaixa("cuba", (0.5, 0.02, 0.36), (0.35, 0.91, 0.02), "metal_claro"),
         gcil("torneira", 0.025, 0.25, (0.35, 1.03, -0.22), "metal_claro", 6)]
    for i in range(3):
        p.append(gcaixa(f"porta{i}", (0.5, 0.7, 0.02), (-0.53 + i * 0.53, 0.43, 0.315), "madeira_media"))
    p.append(gcaixa("escorredor", (0.3, 0.12, 0.25), (-0.45, 0.97, -0.05), "azul_ceu"))
    _fechar("pia_cozinha_01", p)
    gcol("pia_cozinha_01", "", (1.6, 0.92, 0.62), (0, 0.46, 0))


def tv_01():
    p = [gcaixa("rack", (1.4, 0.5, 0.45), (0, 0.25, 0), "madeira_escura", 0.02),
         gcaixa("tela", (1.1, 0.65, 0.06), (0, 0.9, -0.08), "preto", 0.02),
         gcaixa("imagem", (1.0, 0.56, 0.01), (0, 0.9, -0.045), "azul_ceu"),
         gcaixa("pe", (0.25, 0.08, 0.2), (0, 0.54, -0.08), "metal_escuro")]
    for i in range(3):
        p.append(gcaixa(f"livro{i}", (0.06, 0.22, 0.18), (0.45 + i * 0.07, 0.11, 0.05), ["coral", "teal", "amarelo_sol"][i]))
    _fechar("tv_01", p)
    gcol("tv_01", "", (1.4, 1.25, 0.45), (0, 0.625, 0))


def prateleira_01():
    p = [gcaixa("lado_e", (0.04, 1.8, 0.35), (-0.48, 0.9, 0), "madeira_media"),
         gcaixa("lado_d", (0.04, 1.8, 0.35), (0.48, 0.9, 0), "madeira_media"),
         gcaixa("fundo", (1.0, 1.8, 0.02), (0, 0.9, -0.165), "madeira_escura")]
    cores = ["coral", "teal", "amarelo_sol", "azul_tormenta", "roxo", "verde_militar", "vermelho"]
    for n in range(4):
        y = 0.05 + n * 0.55
        p.append(gcaixa(f"tabua{n}", (0.92, 0.03, 0.33), (0, y, 0), "madeira_clara"))
        if n < 3:
            for i in range(6):
                h = 0.26 + (i * 7 % 5) * 0.03
                p.append(gcaixa(f"livro{n}{i}", (0.07, h, 0.24), (-0.36 + i * 0.12 + (n % 2) * 0.05, y + 0.015 + h / 2, 0.0), cores[(i + n * 2) % len(cores)]))
    _fechar("prateleira_01", p)
    gcol("prateleira_01", "", (1.0, 1.8, 0.35), (0, 0.9, 0))


def luminaria_01():
    p = [gcil("base", 0.16, 0.04, (0, 0.02, 0), "metal_escuro", 10),
         gcil("haste", 0.02, 1.4, (0, 0.72, 0), "metal_escuro", 6),
         k.cilindro("cupula", 0.22, 0.28, B((0, 1.5, 0)), "amarelo_sol", lados=10, raio_topo=0.12)]
    _fechar("luminaria_01", p)            # sem colisão


def tapete_01():
    p = [gcaixa("tapete", (2.0, 0.015, 1.4), (0, 0.008, 0), "coral"),
         gcaixa("faixa1", (1.7, 0.017, 0.08), (0, 0.009, 0.4), "amarelo_sol"),
         gcaixa("faixa2", (1.7, 0.017, 0.08), (0, 0.009, -0.4), "amarelo_sol")]
    _fechar("tapete_01", p)               # sem colisão


# ---- loja

def balcao_caixa_01():
    p = [gcaixa("balcao", (2.2, 0.95, 0.7), (0, 0.475, 0), "madeira_media", 0.02),
         gcaixa("tampo", (2.26, 0.05, 0.76), (0, 0.975, 0), "pedra_escura", 0.01),
         gcaixa("faixa", (2.2, 0.12, 0.02), (0, 0.7, 0.355), "teal"),
         gcaixa("caixa", (0.42, 0.22, 0.36), (-0.6, 1.11, -0.05), "metal_escuro", 0.02),
         gcaixa("visor", (0.3, 0.14, 0.03), (-0.6, 1.3, -0.15), "preto"),
         gcaixa("teclas", (0.3, 0.02, 0.15), (-0.6, 1.23, 0.08), "metal_claro"),
         gcaixa("sacola", (0.3, 0.3, 0.18), (0.6, 1.15, 0.0), "amarelo_sol", 0.02)]
    _fechar("balcao_caixa_01", p)
    gcol("balcao_caixa_01", "", (2.2, 1.0, 0.7), (0, 0.5, 0))


def gondola_01():
    p = [gcaixa("base", (1.8, 0.12, 0.6), (0, 0.06, 0), "metal_escuro"),
         gcaixa("painel", (1.8, 1.5, 0.04), (0, 0.75, -0.28), "metal_claro")]
    cores = ["vermelho", "amarelo_sol", "teal", "laranja", "azul_ceu", "rosa", "verde_militar", "coral"]
    for n in range(3):
        y = 0.16 + n * 0.45
        p.append(gcaixa(f"prat{n}", (1.76, 0.03, 0.5), (0, y, 0), "metal_claro"))
        for i in range(7):
            alt = 0.22 if (i + n) % 3 else 0.3
            p.append(gcaixa(f"prod{n}{i}", (0.2, alt, 0.3), (-0.75 + i * 0.25, y + 0.015 + alt / 2, 0.02), cores[(i * 3 + n) % len(cores)], 0.01))
    _fechar("gondola_01", p)
    gcol("gondola_01", "", (1.8, 1.5, 0.6), (0, 0.75, 0))


def expositor_01():
    p = [gcaixa("base", (1.0, 0.75, 1.0), (0, 0.375, 0), "madeira_clara", 0.03),
         gcaixa("vidro", (0.9, 0.3, 0.9), (0, 0.9, 0), "azul_ceu"),
         gcaixa("tampo", (1.0, 0.03, 1.0), (0, 1.065, 0), "madeira_escura")]
    for i, cor in enumerate(("dourado", "coral", "teal", "amarelo_sol")):
        p.append(k.icoesfera(f"item{i}", 0.08, B((-0.25 + (i % 2) * 0.5, 0.85, -0.2 + (i // 2) * 0.4)), cor))
    _fechar("expositor_01", p)
    gcol("expositor_01", "", (1.0, 1.08, 1.0), (0, 0.54, 0))


# ---- indústria (galpões de metal)

def maquina_01():
    p = [gcaixa("base", (1.6, 0.3, 1.0), (0, 0.15, 0), "metal_escuro", 0.02),
         gcaixa("corpo", (1.2, 1.0, 0.75), (-0.1, 0.8, -0.05), "verde_militar", 0.04),
         gcaixa("painel", (0.4, 0.5, 0.08), (0.55, 1.0, 0.3), "metal_claro", 0.02),
         gcaixa("tela", (0.25, 0.15, 0.01), (0.55, 1.12, 0.345), "teal"),
         gcil("botao_v", 0.035, 0.03, (0.48, 0.88, 0.35), "vermelho", 8),
         gcil("chamine", 0.12, 0.4, (-0.4, 1.5, -0.2), "metal_escuro", 8),
         gcaixa("faixa", (1.2, 0.1, 0.77), (-0.1, 0.4, -0.05), "amarelo_sol")]
    p.append(k.cilindro("roda", 0.28, 0.12, B((-0.1, 0.9, 0.38)), "metal_claro", lados=12, rot=(90, 0, 0)))
    _fechar("maquina_01", p)
    gcol("maquina_01", "", (1.6, 1.7, 1.0), (0, 0.85, 0))


def bancada_01():
    p = [gcaixa("tampo", (2.0, 0.08, 0.8), (0, 0.92, 0), "madeira_media", 0.01),
         gcaixa("prateleira", (1.9, 0.04, 0.7), (0, 0.25, 0), "madeira_escura"),
         gcaixa("painel", (2.0, 0.9, 0.04), (0, 1.41, -0.38), "metal_claro")]
    for sx in (-1, 1):
        for sz in (-1, 1):
            p.append(gcaixa(f"pe{sx}{sz}", (0.07, 0.88, 0.07), (sx * 0.93, 0.44, sz * 0.35), "metal_escuro"))
    p += [gcaixa("morsa", (0.25, 0.18, 0.2), (0.7, 1.05, 0.1), "azul_tormenta", 0.02),
          gcaixa("martelo_cabo", (0.04, 0.03, 0.32), (-0.3, 0.98, 0.15), "madeira_clara"),
          gcaixa("martelo_cabeca", (0.12, 0.06, 0.06), (-0.3, 0.99, 0.31), "metal_escuro"),
          gcaixa("chave1", (0.04, 0.3, 0.02), (-0.6, 1.45, -0.35), "metal_escuro"),
          gcaixa("chave2", (0.04, 0.24, 0.02), (-0.45, 1.48, -0.35), "metal_escuro"),
          gcaixa("serrote", (0.3, 0.12, 0.01), (0.1, 1.55, -0.35), "metal_claro"),
          gcaixa("caixa_ferr", (0.4, 0.2, 0.25), (0.2, 0.37, 0), "vermelho", 0.02)]
    _fechar("bancada_01", p)
    gcol("bancada_01", "", (2.0, 0.96, 0.8), (0, 0.48, 0))
    gcol("bancada_01", "_painel", (2.0, 0.9, 0.06), (0, 1.41, -0.38))


def armario_metal_01():
    p = []
    for i in range(3):
        x = -0.5 + i * 0.5
        p.append(gcaixa(f"porta{i}", (0.48, 1.9, 0.5), (x, 0.95, 0), "azul_tormenta" if i != 1 else "teal_escuro", 0.01))
        for n in range(3):
            p.append(gcaixa(f"vent{i}{n}", (0.3, 0.02, 0.01), (x, 1.65 - n * 0.05, 0.255), "metal_escuro"))
        p.append(gcaixa(f"trinco{i}", (0.03, 0.12, 0.03), (x + 0.17, 1.0, 0.26), "metal_claro"))
    _fechar("armario_metal_01", p)
    gcol("armario_metal_01", "", (1.5, 1.9, 0.5), (0, 0.95, 0))


def caixas_01():
    """Pilha de caixotes, centrada (1,2 × 1,0 m)."""
    p = [gcaixa("c1", (0.7, 0.7, 0.9), (-0.25, 0.35, -0.05), "madeira_media", 0.02),
         gcaixa("c2", (0.5, 0.6, 0.6), (0.35, 0.3, 0.15), "madeira_clara", 0.02),
         gcaixa("c3", (0.6, 0.55, 0.6), (-0.25, 0.975, -0.1), "madeira_clara", 0.02)]
    for i, (x, y, z, lx, lz) in enumerate(((-0.25, 0.35, -0.05, 0.7, 0.9), (0.35, 0.3, 0.15, 0.5, 0.6))):
        p.append(gcaixa(f"ripa{i}", (lx + 0.01, 0.06, lz + 0.01), (x, y, z), "madeira_escura"))
    _fechar("caixas_01", p)
    gcol("caixas_01", "", (0.7, 0.7, 0.9), (-0.25, 0.35, -0.05))
    gcol("caixas_01", "_2", (0.5, 0.6, 0.6), (0.35, 0.3, 0.15))
    gcol("caixas_01", "_3", (0.6, 0.55, 0.6), (-0.25, 0.975, -0.1))


def tambores_01():
    """Três tambores de óleo, centrados (1,3 × 1,0 m)."""
    p = []
    for i, (x, z, cor) in enumerate(((-0.35, 0.18, "vermelho"), (0.35, 0.18, "azul_tormenta"), (0.0, -0.2, "amarelo_sol"))):
        p.append(gcil(f"t{i}", 0.3, 0.9, (x, 0.45, z), cor, 12))
        for n in range(2):
            p.append(gcil(f"aro{i}{n}", 0.31, 0.04, (x, 0.25 + n * 0.4, z), "metal_escuro", 12))
    _fechar("tambores_01", p)
    gcol("tambores_01", "", (1.3, 0.9, 1.0), (0, 0.45, 0))


# ---- fazenda (celeiro)

def barril_01():
    p = []
    for i, x in enumerate((-0.32, 0.32)):
        p.append(k.cilindro(f"b{i}", 0.3, 0.9, B((x, 0.45, 0)), "madeira_media", lados=12, raio_topo=0.27))
        for n in range(2):
            p.append(gcil(f"aro{i}{n}", 0.305, 0.04, (x, 0.2 + n * 0.5, 0), "metal_escuro", 12))
    _fechar("barril_01", p)
    gcol("barril_01", "", (1.24, 0.9, 0.6), (0, 0.45, 0))


def sacos_01():
    p = []
    pos = ((-0.4, 0.15, 0.0), (0.35, 0.15, 0.05), (0.0, 0.45, 0.0))
    for i, (x, y, z) in enumerate(pos):
        p.append(k.icoesfera(f"s{i}", 0.4, B((x, y, z)), "areia", escala=(1.0, 0.75, 0.38), ruido=0.06, semente=i))
        p.append(gcaixa(f"amarra{i}", (0.08, 0.05, 0.3), (x + 0.32, y + 0.05, z), "terra"))
    _fechar("sacos_01", p)
    gcol("sacos_01", "", (1.5, 0.75, 0.75), (0, 0.375, 0))


def feno_01():
    p = [gcaixa("fardo", (1.6, 0.85, 0.9), (0, 0.425, 0), "amarelo_sol", 0.06)]
    for i in range(2):
        p.append(gcaixa(f"corda{i}", (0.05, 0.87, 0.92), (-0.4 + i * 0.8, 0.425, 0), "terra"))
    _fechar("feno_01", p)
    gcol("feno_01", "", (1.6, 0.85, 0.9), (0, 0.425, 0))


def ferramentas_01():
    p = [gcaixa("suporte", (1.4, 0.08, 0.12), (0, 1.6, -0.1), "madeira_escura")]
    # forcado, pá e ancinho encostados
    for i, (x, cab) in enumerate(((-0.45, "forcado"), (0.0, "pa"), (0.45, "ancinho"))):
        p.append(gcaixa(f"cabo{i}", (0.04, 1.6, 0.04), (x, 0.85, -0.05), "madeira_clara"))
        if cab == "pa":
            p.append(gcaixa("pa", (0.25, 0.32, 0.02), (x, 0.2, -0.04), "metal_claro"))
        elif cab == "forcado":
            for d in range(3):
                p.append(gcaixa(f"dente{d}", (0.02, 0.3, 0.02), (x - 0.07 + d * 0.07, 0.15, -0.04), "metal_escuro"))
            p.append(gcaixa("trave_f", (0.18, 0.03, 0.03), (x, 0.31, -0.04), "metal_escuro"))
        else:
            p.append(gcaixa("trave_a", (0.4, 0.04, 0.04), (x, 0.08, -0.04), "metal_escuro"))
    p.append(gcaixa("balde", (0.3, 0.3, 0.3), (0.0, 0.15, 0.25), "metal_claro", 0.02))
    _fechar("ferramentas_01", p)
    gcol("ferramentas_01", "", (1.4, 1.7, 0.25), (0, 0.85, -0.05))


MOVEIS = (sofa_01, mesa_01, cadeira_01, cama_01, armario_01, geladeira_01, fogao_01, pia_cozinha_01, tv_01,
          prateleira_01, luminaria_01, tapete_01, balcao_caixa_01, gondola_01, expositor_01, maquina_01,
          bancada_01, armario_metal_01, caixas_01, tambores_01, barril_01, sacos_01, feno_01, ferramentas_01)


GERADORES = {f.__name__: f for f in MOVEIS + (escada_madeira_01, escada_concreto_01, escada_metal_01,
                                      escada_madeira_topo_01, escada_concreto_topo_01, escada_metal_topo_01)}


def main():
    for asset_id in sys.argv[1:] or list(GERADORES):
        k.nova_cena()
        GERADORES[asset_id]()
        k.salvar("cenario", asset_id)


if __name__ == "__main__":
    main()
