# Licenças de Assets — Projeto Ventania

## 1. Política

1. **Todo asset distribuído com o jogo** (modelo, textura, animação, som, música, fonte, ícone, shader) precisa ser:
   - criado para este projeto, **ou**
   - CC0 / domínio público, **ou**
   - de licença que permita uso e redistribuição em jogos (CC-BY com atribuição, OFL para fontes, MIT etc.).
2. **Nenhum arquivo da Epic Games ou do Fortnite** (extraído, "vazado" ou de dumps públicos) entra no repositório, nem mesmo como "referência" dentro do projeto. Estar disponível publicamente **não** é uma licença. Também não serão recriados de forma reconhecível personagens, skins, itens, mapas e locais nomeados, sons, músicas, logotipos ou layouts de interface desse jogo.
   - Proporções, legibilidade e técnicas de otimização serão estudadas a partir de material de domínio geral (documentação do Godot, palestras de GDC, tutoriais de low-poly), não de arquivos proprietários.
3. **Nomes originais:** nenhum nome de item, arma, moeda, local ou personagem será copiado de outro jogo.
4. Cada pasta em `game/assets/` terá um `LICENSES.json` com uma entrada por arquivo, e um script em `tools/` (Etapa 1) vai recusar o build se houver asset sem registro.
5. Nada é listado como disponível sem estar de fato no repositório.

## 2. Formato do registro (`LICENSES.json`)

```json
[
  {
    "file": "characters/base_body.glb",
    "author": "Nome ou equipe",
    "source": "original | URL de origem",
    "license": "CC0-1.0 | CC-BY-4.0 | OFL-1.1 | Original",
    "attribution": "Texto exigido pela licença, se houver",
    "modified": true,
    "notes": ""
  }
]
```

## 3. Assets presentes no repositório

| Arquivo | Autor | Origem | Licença |
|---|---|---|---|
| `game/assets/baus_coletaveis/caixote_exemplo_01.glb` (+ textura extraída) | Projeto Ventania (gerado por `tools/assets/blender/make_sample_crate.py`) | Original | Original. Asset de teste do pipeline, não é final |
| Kit visual: 18 GLB em `game/assets/{construcoes,cenario,baus_coletaveis,personagens}/` | Projeto Ventania (gerados por `tools/assets/kit/blender/*.py`) | Original | Original |
| `game/assets/ui/fontes/fredoka_500.woff2`, `fredoka_700.woff2` | The Fredoka Project Authors | npm `@fontsource/fredoka` 5.3.0 (subset latin) | OFL-1.1 (texto em `game/assets/ui/fontes/OFL.txt`) |
| `game/assets/audio/ui/*.wav` | Projeto Ventania (`tools/audio/gerar_sons_ui.py`, síntese) | Original | Original |
| `game/assets/audio/jogo/*.wav` (31 efeitos, incluindo golpes da picareta por material e sons do inventário) | Projeto Ventania (`tools/audio/gerar_sons_jogo.py`, síntese) | Original | Original |
| `game/assets/armas/picareta_01.glb` (picareta permanente, 532 triângulos) | Projeto Ventania (`tools/assets/kit/blender/gerar_armas.py`) | Original | Original. Design próprio; variações cosméticas futuras usam os mesmos marcadores |
| `game/assets/ui/icones/*.png` (miniaturas do inventário, incluindo a picareta) | Projeto Ventania (`game/tests/gerar_icones.gd`, renderizadas dos modelos originais) | Original | Original |
| `game/data/nomes_jogadores.txt` (1000 nomes de jogadores dos bots) | Lista fornecida pelo dono do projeto | Projeto | Uso no projeto |
| Skins da Etapa 13: 9 trajes, `picareta_ancora_01`, `planador_arraia_01`, `planador_folha_01`, peixes do aquário | Projeto Ventania (`tools/assets/kit/blender/gerar_skins.py`) | Original | Original. Conceitos próprios, sem personagens de outros jogos |
| `game/assets/texturas_materiais/vidro_aquario.gdshader`, `agua_aquario.gdshader`, `M_vidro_ventania.tres`, `M_agua_ventania.tres` | Projeto Ventania | Original | Original |
| `game/assets/ui/loja/*.png` (imagens dos cosméticos) e `game/ui/shared/fundo_cosmetico.gdshader` | Projeto Ventania (`game/tests/gerar_imagens_loja.gd`, renderizadas dos modelos originais) | Original | Original |
| `game/assets/ui/icone.png` | Projeto Ventania (`tools/assets/kit/gerar_icone.py`) | Original | Original |
| `game/assets/texturas_materiais/paleta_ventania.png`, `toon_paleta.gdshader`, `M_paleta_ventania.tres` | Projeto Ventania | Original | Original |

A fonte da verdade é `assets_catalog.json`. Os `game/assets/<cat>/LICENSES.json`
são gerados por `python3 tools/assets/catalog.py licencas`, e o validador do
catálogo rejeita origens proprietárias e licenças fora da lista permitida
(`tools/assets/budgets.json`). As regras para referências visuais de estudo estão
em `docs/assets/REFERENCIAS.md`.

## 4. Fontes candidatas (a verificar item a item antes do uso)

Estas são **candidatas**, não assets já incluídos. A licença de cada arquivo deve
ser conferida na origem no momento do download.

| Tipo | Fonte candidata | Licença usual |
|---|---|---|
| Modelos low-poly, props, UI, áudio | Kenney (kenney.nl) | CC0 |
| Personagens e animações low-poly | Quaternius | CC0 |
| Modelos variados | Poly Pizza | Varia por modelo (CC0 / CC-BY) |
| Texturas | ambientCG, Poly Haven | CC0 |
| Efeitos sonoros | Freesound (filtrar por CC0/CC-BY) | Varia |
| Fontes | Google Fonts | OFL / Apache 2.0 |
| Criação própria | Blender (ferramenta) | Assets resultantes: originais |

Atenção: alguns serviços de animação gratuitos permitem uso em jogos, mas proíbem
redistribuir os arquivos brutos. Só serão usados se a licença permitir a
distribuição dentro do pacote do jogo.

## 5. Atribuições exigidas

- **Fredoka:** Copyright 2016 The Fredoka Project Authors. Licenciada sob a SIL Open Font License 1.1. Também exibida em Configurações → Servidor.
