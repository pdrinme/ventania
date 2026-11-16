# Importação na Godot e otimização para hardware modesto

Alvo: renderizador **Compatibility** (OpenGL ES 3 / GL 3.3), Android de 2–4 GB e
GPUs integradas antigas. Ver também ARCHITECTURE.md §9.

## 1. Como a importação está configurada

Em `game/project.godot`, `[importer_defaults]`, que vale para todo GLB novo:

| Opção | Valor | Efeito |
|---|---|---|
| `import_script/path` | `res://pipeline/post_import.gd` | Desliga sombra de objetos pequenos, aplica `visibilidade_m` e grava estatísticas |
| `meshes/generate_lods` | ligado | A Godot gera LODs automáticos da malha (decimação), escolhidos pela distância |
| `meshes/create_shadow_meshes` | ligado | Malha de sombra simplificada (menos vértices no passe de sombra) |
| `meshes/light_baking` | desligado | Sem lightmaps por enquanto |
| `gltf/embedded_image_handling` | Extrair texturas | As texturas viram arquivos `.png` com import próprio e **compressão VRAM** |
| texture `compress/mode` | VRAM Compressed | S3TC/BPTC no PC, ETC2/ASTC no Android (ambos ativados em `[rendering]`) |
| texture `mipmaps/generate` | ligado | Menos aliasing e menos banda de memória à distância |

**Na prática:** copie o GLB para `game/assets/<categoria>/`. A Godot importa
sozinha ao abrir o editor (ou com `godot --headless --path game --import`). Para
usar o asset, instancie o `.glb` como cena, ou clique duas vezes nele e use
**"Advanced Import Settings"** para ajustes por arquivo (física, LOD, materiais
externos).

**Materiais externos:** para trocar o material importado por um feito na Godot
(ex.: um shader cartoon compartilhado), use *Advanced Import Settings* → Material
→ "Use External" e aponte para um `.tres` em
`game/assets/texturas_materiais/`. Materiais compartilhados entre assets reduzem
trocas de estado na GPU.

## 2. Geometria

| Regra | Motivo |
|---|---|
| Respeite os orçamentos de `tools/assets/budgets.json` (ex.: personagem 6k tris, arma 1,5k, peça de construção 300) | Os triângulos custam vértices em GPU fraca, e a área sombreada custa mais ainda |
| Silhueta primeiro: detalhe pequeno vai para a **textura**, não para a malha | O estilo cartunesco favorece formas grandes e simples |
| Remova faces que nunca aparecem (base de props apoiados, interior) | Polígonos e overdraw desperdiçados |
| Junte as partes de um prop em **um objeto e um material** | 1 malha + 1 material = 1 draw call |
| Colisão: malha `-colonly` com poucas caixas/convexos, nunca a malha visual | A física no servidor e nos bots fica barata |
| Personagens: no máximo 4 influências por vértice e até 60 ossos | É o limite do skinning eficiente em GLES3 |
| Objetos repetidos (árvores, pedras, peças de construção) serão desenhados com **MultiMesh** | Milhares de instâncias em poucos draw calls (implementado nas Etapas 4/5) |
| LOD: automático da Godot. LODs manuais só para personagens, se a medição pedir | Menos trabalho de arte |
| Distância de visibilidade (`visibilidade_m`) em props pequenos | Objetos pequenos somem a distância em vez de ocupar a GPU |

## 3. Texturas

| Regra | Motivo |
|---|---|
| **Atlas:** uma textura pequena com blocos/gradientes de cor compartilhada por vários assets | Menos materiais, menos draw calls, combina com o visual cartunesco |
| Tamanhos em potência de 2: 128/256/512 (1024 só para personagens) | Compressão ETC2/S3TC e mipmaps eficientes |
| Sem textura onde a cor sólida basta (cor do vértice ou cor do material) | Zero memória de textura |
| Normal maps: evitar. Se necessário, ≤ 256 px | Custo de amostragem e memória. O estilo usa sombreamento simples |
| Mapas ORM (oclusão/rugosidade/metal) só se fizerem diferença visível | Em GLES3 cada amostra conta |
| Alfa: preferir **alpha scissor** (recorte) a blend | Transparência com blend quebra ordenação e causa overdraw |
| Orçamento de memória: textura RGB 512² ETC2 ≈ 170 KB com mipmaps | Planeje o total do mapa para ≤ 150 MB de texturas no perfil Performance |

## 4. Materiais e shaders

- Use `StandardMaterial3D` simples ou um shader cartoon **único** do projeto (Etapa 2), com poucas variações.
- Desligue o que não for usado: emissão, rim light, clearcoat, refração, subsurface scattering, normal map.
- **Sem transparência** em grandes áreas. Folhagem com alpha scissor.
- Prefira "Shading Mode: Per-Vertex" nos perfis baixos, para props distantes (o perfil de gráficos da Etapa 1 decide isso).
- Iluminação: uma luz direcional e ambiente fixo. Sombras configuráveis por perfil, e objetos pequenos sem sombra (o `post_import.gd` já faz isso abaixo de 0,5 m de raio).

## 5. Animações

- Taxa de 30 FPS no Blender, com "Optimize Animation Size" ligado (já no exportador).
- Animações do jogador em GLB separados, compartilhando o esqueleto padrão: um ciclo por arquivo ou várias *actions* em um arquivo, com sufixo `-loop` nos ciclos (a Godot marca o loop sozinha).
- Emotes são cosméticos e usam o mesmo esqueleto. Não alteram hitbox.
- No servidor, só a pose necessária para hitboxes. Os efeitos visuais de animação ficam só no cliente.

## 6. Como medir

- Na Godot, o painel *Debugger → Monitors* mostra draw calls, objetos, vértices e memória de vídeo.
- A cena de benchmark com trajeto fixo e saída em CSV é feita na Etapa 2 e usada a cada etapa de gameplay.
- Um asset só passa para `otimizado` no catálogo depois de visto dentro do orçamento em uma cena real.
