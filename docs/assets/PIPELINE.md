# Pipeline de assets 3D

Da referência visual ao asset otimizado na Godot.

```
 referência visual       autoria original          exportação        importação        jogo
 (references/, local) ─► assets_src/<cat>/*.blend ─► GLB ──────────► game/assets/ ───► cenas
                         Blender                    export_glb.py     Godot +           (Etapas 2+)
                                                    + orçamentos      post_import.gd
                         catálogo: planejado → blockout → modelado → texturizado → exportado → importado → otimizado → aprovado
```

## 1. Estrutura de diretórios

| Pasta | Conteúdo | Versionada? |
|---|---|---|
| `references/<cat>/` | Referências visuais de **estudo** (capturas, fotos, moodboards, anotações) | **Não** (`.gitignore`), só o README |
| `assets_src/<cat>/` | Arquivos de autoria (`.blend`, texturas fonte `.png`/`.kra`) | Sim (Git LFS) |
| `game/assets/<cat>/` | GLB exportados + texturas extraídas + `LICENSES.json` | Sim (Git LFS) |
| `tools/assets/` | Scripts de exportação, validação, catálogo, orçamentos | Sim |
| `game/pipeline/` | Script de pós-importação da Godot | Sim |
| `assets_catalog.json` | Catálogo de todos os assets do jogo | Sim |

Categorias (iguais nas três árvores): `personagens`, `armas`,
`mochilas_acessorios`, `construcoes`, `cenario`, `baus_coletaveis`,
`texturas_materiais`, `animacoes`.

## 2. Formatos

| Uso | Formato | Por quê |
|---|---|---|
| **Troca Blender → Godot** | **GLB (glTF 2.0 binário)** | Padrão aberto, importador nativo e maduro na Godot 4. Carrega malha, materiais PBR, esqueleto, animações e propriedades customizadas em um arquivo só. |
| Autoria | `.blend` | Arquivo fonte editável. A Godot até importa `.blend` direto, mas isso exige o Blender instalado em toda máquina que abre o projeto, por isso não usamos. |
| Texturas fonte | PNG (8 bits), `.kra`/`.psd` opcionais | Sem perda. A Godot recomprime na importação. |
| Texturas na GPU | Geradas pela Godot: S3TC/BPTC (PC), ETC2/ASTC (Android) | Ativado em `project.godot`. Nunca versionar `.dds`/`.ktx` manualmente. |
| Animações | Dentro do GLB do personagem, ou GLB só de animação com o **mesmo esqueleto** | Godot importa como `AnimationLibrary`. |
| Áudio (futuro) | OGG Vorbis (música/ambiente), WAV curto (efeitos) | Suporte nativo. |

**Evitar:**
- **FBX:** a Godot usa um conversor (ufbx). Funciona, mas é menos previsível que o glTF. Use só se um asset licenciado vier apenas em FBX: reexporte para GLB pelo Blender.
- **OBJ:** sem esqueleto, sem animação e sem hierarquia.
- **Draco e meshopt** (`KHR_draco_mesh_compression`, `EXT_meshopt_compression`): **não são lidos pela Godot**. O `export_glb.py` desliga e o `validate_glb.py` rejeita.
- **glTF separado** (`.gltf` + `.bin` + imagens): funciona, mas espalha arquivos. Padronizamos GLB.

## 3. Convenções no Blender

- **Unidade:** metros, escala da cena 1,0. **Escala dos objetos aplicada** (Ctrl+A → Escala). O exportador falha se não estiver.
- **Eixos:** modele com Z para cima e frente em −Y. O exportador converte para o Y-up da Godot.
- **Origem:** na base do objeto (pés do personagem, chão do prop). Para peças de construção, no canto da célula da grade (4 m).
- **Nomes:** `snake_case`. Objeto principal = id do asset (`caixote_exemplo_01`).
- **Sufixos reconhecidos pela Godot:**
  - `-colonly`: vira só colisão (malha simplificada).
  - `-convcolonly`: colisão convexa.
  - `-col`: malha visível + colisão.
  - `-noimp`: não importa.
- **Sufixos do projeto:**
  - `-noexport`: o `export_glb.py` ignora.
  - `-noshadow`: o `post_import.gd` desliga a sombra.
- **Propriedades customizadas** (painel Object → Custom Properties) chegam como metadado `extras` na Godot. Exemplos: `visibilidade_m = 80` (distância máxima de renderização) e `interacao = "abrir"`.
- **Personagens:** um **esqueleto padrão único** para todos os trajes (definido na Etapa 2), com até 60 ossos e pesos de no máximo 4 ossos por vértice.
- **Materiais:** um material por asset, sempre que possível, usando um atlas de textura (ver o documento de otimização).

## 4. Passo a passo de um asset

```bash
python3 tools/assets/catalog.py novo --id barril_01 --nome "Barril" --categoria cenario --origem original --autor "Seu nome" --licenca Original
```

1. Coloque as referências visuais em `references/cenario/` (local, não vai para o git).
2. Modele em `assets_src/cenario/barril_01.blend` e avance o estado no catálogo a cada fase:

```bash
python3 tools/assets/catalog.py estado barril_01 blockout
```

3. Exporte (o script checa os orçamentos antes de exportar):

```bash
blender -b assets_src/cenario/barril_01.blend -P tools/assets/blender/export_glb.py -- --categoria cenario --id barril_01
```

4. Valide e marque no catálogo:

```bash
python3 tools/assets/validate_glb.py --todos
```

```bash
python3 tools/assets/catalog.py estado barril_01 exportado
```

5. Abra a Godot, ou rode a importação headless, e execute o teste de importação:

```bash
godot --headless --path game --import
```

```bash
godot --headless --path game -s res://tests/test_asset_import.gd
```

6. Regenere os `LICENSES.json` e valide o catálogo inteiro:

```bash
python3 tools/assets/catalog.py licencas
```

```bash
python3 tools/assets/catalog.py validar
```

## 5. Catálogo (`assets_catalog.json`)

Campos de cada asset:

| Campo | Descrição |
|---|---|
| `id` | Identificador único (`[a-z0-9_]`), igual ao nome do arquivo |
| `nome` | Nome legível |
| `categoria` | Uma das 8 categorias |
| `origem` | `original` ou `terceiros_licenciado` |
| `autor` | Quem criou |
| `licenca` | `Original`, `CC0-1.0`, `CC-BY-4.0`, `OFL-1.1`, `MIT`… (lista em `tools/assets/budgets.json`) |
| `url_origem`, `atribuicao` | Obrigatórios para assets de terceiros (atribuição só para CC-BY) |
| `arquivo_fonte`, `arquivo_exportado` | Caminhos no repositório |
| `estado` | `planejado` → `blockout` → `modelado` → `texturizado` → `exportado` → `importado` → `otimizado` → `aprovado` |
| `referencias` | Lista de descrições textuais das referências de estudo usadas (não os arquivos) |
| `notas`, `atualizado_em` | Livres / data automática |

O catálogo **só aceita assets que podem ser distribuídos**. Origens
proprietárias ou licenças desconhecidas são rejeitadas pelo validador.

## 6. Ferramentas necessárias

| Ferramenta | Versão testada | Para quê |
|---|---|---|
| Blender | 5.3 (via módulo `bpy` 5.3.0) | Modelagem, UV, rigging, exportação GLB |
| Godot | 4.7.2-stable | Importação e jogo |
| Python | 3.11+ | `validate_glb.py`, `catalog.py`, testes |
| Git + Git LFS | — | Versionar binários (`.gitattributes` já configurado) |

Para rodar o Blender sem interface (CI ou servidor) sem instalá-lo:

```bash
python3.13 -m venv .venv-bpy
```

```bash
.venv-bpy/bin/pip install bpy==5.3.0
```

```bash
.venv-bpy/bin/python tools/assets/blender/export_glb.py --blend <arquivo.blend> --categoria <cat> --id <id>
```

## 7. Testes do pipeline

```bash
python3 -m unittest discover -s tools/assets/tests -v
```

Validam o leitor e os orçamentos de GLB, a rejeição de Draco, as regras do
catálogo e a rejeição de origens e licenças não permitidas. O teste
`game/tests/test_asset_import.gd` verifica que todo GLB importa, que o script de
pós-importação rodou e que as texturas foram extraídas (o que permite compressão
na GPU).

O asset `caixote_exemplo_01` (gerado por código em
`tools/assets/blender/make_sample_crate.py`, original) existe só para testar a
cadeia inteira e pode ser apagado quando houver assets reais.
