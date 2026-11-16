# Roadmap — Projeto Ventania

Legenda: ✅ concluído e testado · 🟡 em andamento · ⬜ não iniciado.
**Nada é marcado ✅ sem teste executado.**

## Marcos

- **M1 — "Jogável com amigos"** (Etapas 1–7): partida Battle Royale em servidor dedicado, com 2–4 humanos e bots, combate, construção e Tormenta. Esse é o primeiro objetivo real.
- **M2 — "Jogo completo"** (Etapas 8–11): lobby real, contas, grupos, progressão, passe e loja.
- **M3 — "Distribuível"** (Etapa 12): builds para Windows, Linux e Android, além do guia para os amigos.

## Ajuste proposto à ordem original (aguarda aprovação)

| Mudança | Motivo |
|---|---|
| A partir da **Etapa 2**, o gameplay roda como servidor autoritativo em processo (loopback ENet), mesmo jogando sozinho. | Adaptar rede depois força reescrever personagem, armas, construção e bots. Com o caminho de rede desde o início, a Etapa 7 vira endurecimento em vez de reescrita. |
| A **Etapa 1** inclui o esqueleto do meta-servidor (health check, versão, conta de teste). | "Estrutura de comunicação com o servidor" precisa de um servidor real para ser testada. É um esqueleto, não o lobby. |
| Cada etapa de gameplay termina com uma **medição de desempenho** na cena de benchmark. | A otimização é prioridade desde o início, não um polimento final. |

## Etapas

### Etapa 0 — Auditoria e planejamento ✅
- ✅ Auditoria: diretório vazio, sem código anterior e sem repositório git.
- ✅ Engine verificada: Godot 4.7.2-stable baixado e executado em modo headless.
- ✅ Teste técnico: conexão ENet cliente-servidor em loopback com sucesso.
- ✅ Documentos: README, ARCHITECTURE, GAME_DESIGN, ROADMAP e ASSET_LICENSES.
- ✅ Código versionado em github.com/pdrinme/ventania (privado).

### Etapa 0.5 — Pipeline de assets ✅
- ✅ Estrutura `references/` (local, fora do git), `assets_src/` e `game/assets/`, com 8 categorias.
- ✅ `export_glb.py`, testado com o Blender 5.3 (módulo bpy): exporta .blend → GLB com checagem de orçamento.
- ✅ `validate_glb.py` e `catalog.py` (só stdlib), com 12 testes unitários passando.
- ✅ Godot: `project.godot` mínimo (Compatibility, compressão ETC2/S3TC, `[importer_defaults]`) e `post_import.gd`. O teste headless de importação passa.
- ✅ Asset de teste original `caixote_exemplo_01` percorreu toda a cadeia (60 tris, 1 material, textura 128², colisão).
- ✅ Docs: `docs/assets/PIPELINE.md`, `IMPORTACAO_GODOT_E_OTIMIZACAO.md` e `REFERENCIAS.md`.
- ⛔ Não feito (por decisão de licenciamento): guia de extração de builds do Fortnite com FModel ou ferramentas de porting. Ver `docs/assets/REFERENCIAS.md`.
- ⬜ Pendente: o esqueleto padrão de personagem fica para a Etapa 2. Orçamentos ainda não validados em hardware real.

### Etapa 0.6 — Kit visual cartunesco original ✅
- ✅ Paleta única de 40 cores (`tools/assets/kit/paleta.json`) → atlas 256² gerado só com stdlib.
- ✅ Shader cartoon `toon_paleta.gdshader` (2 faixas, sombra azulada, rim) e material compartilhado, trocado na importação pelo `post_import.gd`.
- ✅ 18 assets originais gerados por código: 12 peças de construção (parede, piso, rampa, teto × madeira, pedra, metal), 4 props de cenário, o baú com tampa animada e o personagem-base com esqueleto humanoide padrão (20 ossos) e as animações `idle` (loop) e `acenar`.
- ✅ Todos dentro do orçamento, importados na Godot e registrados no catálogo (estado `importado`).
- ✅ Vitrine renderizada na Godot (Compatibility): Quality com 58 draw calls e ~17,6k primitivas, Performance com 29 draw calls e ~8,8k.
- ✅ `docs/art/GUIA_DE_ESTILO.md`.
- ⬜ Pendente: validar o visual e o FPS em hardware real (Android e GPU integrada), usar MultiMesh para as peças repetidas (Etapas 4/5), e criar armas, mochilas, trajes variantes e casas.

### Etapa 1 — Fundação ✅
- ✅ Estrutura do projeto: `autoload/`, `core/`, `ui/`, `scenes/`, `world/`, `tests/`, além de `backend/`.
- ✅ Gerenciamento de cenas com carregamento em segundo plano e tela de carregamento (`SceneManager`, `AsyncLoader`).
- ✅ Configurações: 3 perfis (Desempenho, Equilibrado, Qualidade) e opções independentes, validadas por esquema e salvas de forma atômica em `user://settings.json`. São aplicadas na janela, nas sombras, na distância de visão (com neblina de profundidade) e no áudio.
- ✅ Áudio: barramentos Master, Música, Efeitos e Interface, com sons de interface originais.
- ✅ Entrada: 28 ações com teclado, mouse e controle, remapeamento com detecção de conflito e detecção de dispositivo.
- ✅ Estrutura de dados do jogador (`PlayerProfile`, um cache validado; a fonte da verdade fica no servidor) e salvamento seguro (`SafeFile`).
- ✅ Comunicação com o servidor: `MetaApi` (HTTP/JSON com timeout e checagem de protocolo) e meta-servidor em Python stdlib (`/v1/health`, `/v1/compat`, SQLite com migrações).
- ✅ Interface: tema próprio (fonte Fredoka OFL) e menu com o personagem 3D. A tela de configurações tem layout diferente no PC e no celular.
- ✅ Vitrine e teste de desempenho (20 s, com resultado em JSON/CSV e cópia do resumo) para hardware real.
- ✅ Testes: 12 de assets, 8 do backend, 24 unitários na Godot, fumaça do jogo completo e integração cliente↔servidor (`tools/run_tests.sh`). A build Linux exportada também passa no teste de fumaça.
- ✅ Exportação: builds de Windows e Linux geradas.
- ⚠️ Não testado: a build de Windows (não há Windows nem Wine no ambiente de desenvolvimento).
- ⬜ Pendente: APK Android (depende do Android SDK e do aceite da licença do Google, ver `docs/TESTE_EM_HARDWARE.md`), medições em hardware real, e layout de toque (Etapa 2).

### Medições em hardware real
| Data | Aparelho | Perfil | FPS médio / 1% pior | Observação |
|---|---|---|---|---|
| 2026-11-16 | i5-2415M + Intel HD Graphics 3000, Linux (v0.1.0) | Desempenho | 30 / 30 | Preso no limite de 30 FPS do perfil |
| 2026-11-16 | idem | Equilibrado | 60 / 60 | Preso no limite de 60 / vsync |
| 2026-11-16 | idem | Qualidade | 39,6 / 37,8 | Limitado pela GPU (sombras altas + MSAA 2x + 100%) |

| 2026-11-16 | i5-2415M + HD Graphics 3000, Linux (v0.1.1, sem limite) | Desempenho | 105,9 / 90,3 | Folga grande |
| 2026-11-16 | idem | Equilibrado | 69,9 / 51,3 | No limite; "1% pior" abaixo de 60 |
| 2026-11-16 | idem | Qualidade | 38,1 / 35,0 | Limitado pela GPU |

**Decisões:** no PC, o perfil Desempenho passa a limitar em 60 FPS (no celular continua em 30). O padrão do PC continua Equilibrado por enquanto, mas deve ser revisto quando o gameplay existir: se máquinas como esta caírem abaixo de 60, o padrão vira Desempenho, ou entra uma detecção automática de perfil no primeiro uso.
**Pendente:** densidade 2×2 e 3×3, e o celular.

### Etapa 2 — Personagem e gameplay básico ✅
- ✅ Personagem em terceira pessoa com a câmera por cima do ombro (mira com zoom, colisão da câmera com paredes, troca suave de altura ao agachar).
- ✅ Movimento: andar 4,5 m/s, correr 6,5 m/s (só para a frente), agachar 2,5 m/s (sem levantar embaixo de teto), pulo de ~1,4 m e rampas de 45°.
- ✅ Animações originais: idle, andar, correr, agachado, agachado andando, no ar e acenar, escolhidas pelo estado e com velocidade do ciclo ajustada.
- ✅ **Rede desde o início**: servidor autoritativo (ENet, 30 Hz, snapshots a 15 Hz). O cliente prevê o próprio movimento e reconcilia a cada snapshot. Os outros jogadores são interpolados ~150 ms atrás.
- ✅ Treino local (servidor no mesmo processo, num mundo físico separado), "Entrar em servidor" (IP:porta) e servidor dedicado (`-- --servidor`) no mesmo executável.
- ✅ Controles de PC (teclado/mouse com mouse capturado, controle) e de toque (joystick flutuante, olhar arrastando, Pular, Agachar, corrida ao empurrar o joystick até a borda), com tamanho ajustável.
- ✅ Campo de treino: cabana, torre de 8 m com rampas, caixa de metal, túnel baixo e 40 props, todos com colisão.
- ✅ HUD (mira, ping, jogadores, dicas por dispositivo) e pausa (Esc, Start ou botão voltar do Android).
- ✅ Testes:
  - 38 unitários, incluindo o protocolo e o movimento (determinismo, altura do pulo, teto);
  - fumaça jogando de verdade: andar, pular, predição sem correções, servidor sem perder entradas, 2º jogador entra e sai;
  - servidor dedicado em outro processo com 2 clientes;
  - desempenho do servidor: 24 jogadores em ~1 ms por tick (3% do orçamento).
- ⚠️ Não validado em hardware real: o FPS jogando no seu notebook e no celular (o APK ainda depende do SDK).
- ⬜ Pendente para etapas futuras: as animações ainda são provisórias e rígidas, não há suavização visual das correções (até agora não foram necessárias) e não há escolha de servidor por lista (só IP:porta).

**Problemas encontrados e resolvidos nesta etapa:**
1. O ENet limitava os pacotes não confiáveis a ~1/32 depois de 1 s (o ajuste de banda por host). Corrigido com `bandwidth_limit(0, 0)` nos dois lados e o throttle por conexão desligado.
2. O "grudar no chão" nativo do CharacterBody3D depende de estado interno que não viaja pela rede e quebrava a predição. Agora o snap é feito manualmente e é determinístico.
3. O servidor inventava passos quando uma entrada atrasava. Agora ele espera até ~200 ms e processa duas entradas por tick para recuperar o atraso.
4. O HUD tinha tamanho zero (`set_anchors_preset` preserva o tamanho) e não herdava o tema dentro de CanvasLayer. Corrigido.

### Etapa 3 — Combate e inventário ✅
- ✅ 5 armas originais: Rajada (fuzil), Trovão (escopeta, 10 projéteis), Zumbido (submetralhadora), Faísca (pistola) e Gavião (precisão, exata quando mirando). Modelos próprios, que aparecem na mão do personagem, com animações de locomoção "segurando arma".
- ✅ 5 raridades (Comum → Lendário) que aumentam o dano e reduzem o tempo de recarga. Os dados ficam em `data/itens.json`, para balancear sem mexer no código.
- ✅ Disparo **decidido no servidor**: o raio passa pela mira, a dispersão é determinística (cliente e servidor calculam os mesmos traçantes) e varia ao mirar, mover, agachar e estar no ar. As paredes bloqueiam o tiro, e há bônus na cabeça.
- ✅ **Compensação de latência**: o servidor testa o tiro contra onde o alvo estava na tela de quem atirou (até 400 ms), com hitboxes analíticas iguais para todos os trajes.
- ✅ Munição de 4 tipos (reserva separada), recarga (manual e automática com o pente vazio), armas automáticas e semiautomáticas.
- ✅ Vida 100 e escudo 100 (o escudo absorve primeiro). Consumíveis: curativo (+15 até 75), kit de cura (+100), célula pequena (+25 de escudo até 50) e grande (+50 até 100), com tempo de uso.
- ✅ Inventário de 5 espaços: troca pelo espaço selecionado quando cheio, consumíveis empilham e a munição é coletada ao passar por cima.
- ✅ Baús (segurar Interagir por 0,5 s), loot no chão sorteado por raridade e itens largados ao ser eliminado. No treino, os baús reabastecem e o jogador reaparece em 4 s com uma pistola.
- ✅ Bonecos de treino (alvos com escudo, que se regeneram).
- ✅ HUD: vida e escudo, 5 espaços com a cor da raridade, munição, barra de recarga/uso, aviso de interação, feed de eliminações, tela de eliminado, marcador de acerto (amarelo na cabeça), números de dano, flash de dano e nome sobre os jogadores. Controles de toque: Atirar (arrastar o dedo nele também mira), Recarga, Pegar e toque nos espaços.
- ✅ Testes:
  - 53 unitários (itens, inventário, vida/escudo, hitbox, dispersão, protocolo v2, loot e baús);
  - fumaça atirando num boneco;
  - **jogador contra jogador no servidor dedicado** (3 acertos, 72 de dano confirmados).
- ⚠️ Não validado em hardware real: o celular (APK 0.3.0 gerado), o tiroteio com latência real de internet e o Windows.
- ⬜ Pendente:
  - sons de tiro e de acerto (Etapa 12);
  - o ângulo da arma na mão e animações de disparo/recarga;
  - o efeito da distância no dano;
  - lista de "quem me acertou" (direção do dano).

**Problemas encontrados e resolvidos:** o tamanho da mensagem de tiro estava errado (os traçantes dos outros eram descartados); o executor contava como aprovado um teste interrompido por erro de script (agora qualquer `SCRIPT ERROR` reprova); a arma pedida antes do visual ficar pronto era ignorada; e o atalho de interagir no controle colidia com o de recarregar (agora é o Y).

### Etapa 3 — Revisão e polimento (v0.3.1) ✅
| Problema relatado | Causa encontrada | Correção |
|---|---|---|
| Arma solta/estranha na mão | A arma ficava presa ao osso da mão e seguia uma pose fixa dos braços, sem relação com a empunhadura real. | Sistema novo: o **ItemRig** coloca o item na pose da categoria e **IK nos dois braços** (TwoBoneIK3D) leva as mãos aos marcadores do modelo (`grip_r`, `grip_l`). As armas longas ficam junto ao corpo, porque o braço (0,58 m) não alcançava o guarda-mão. |
| Tampa do baú solta, flutuando | No gerador do Blender, juntar peças herdava a origem da primeira peça, e a tampa ficava 0,59 m deslocada do próprio pivô. | `unir()` grava a origem no mundo e `origem_em()` move a origem da tampa para a dobradiça. Medição: a tampa vai de 0,50 a 0,68 m fechada e gira presa. |
| Colisões das construções | O mesmo erro de origem desalinhava visual e colisão (até 1,7 m). As colisões eram malhas ocas (`-colonly`), o telhado era uma placa sob uma pirâmide de 1,6 m, e o personagem travava na emenda rampa→piso. | Peças refeitas com padrões de grade (piso com topo a 0,10 m; parede de 0,24 m com detalhes dentro; rampa de topo a topo; telhado em pirâmide). Colisões **convexas sólidas** iguais ao visual e bordas do piso chanfradas. |
| Animações rígidas | Ciclos simples com poucas chaves e sem transições. | Animações refeitas (passada com contato e empurrão, quadril, giro do tronco, braços com atraso; corrida; pulo, queda e aterrissagem; idle com peso e respiração), com AnimationTree (misturas sincronizadas e one-shots), tronco e cabeça seguindo a mira, e ações procedurais (recarga por categoria, uso de consumíveis, troca, recuo e clarão, alcance do baú). |
| Nomes genéricos | Só o nome próprio. | "Rifle de Assalto Rajada", "Espingarda Trovão", "Submetralhadora Zumbido", "Pistola Faísca" e "Rifle de Precisão Gavião" em todo o jogo (`ItemDB.display_name`). |
| Inventário pouco legível | Botões de texto. | Miniaturas renderizadas dos modelos, fundo em degradê por raridade, Mítico animado, espaço selecionado ampliado e o nome completo na cor da raridade. |
| *(achado na verificação)* Build de release travava ao **fechar o jogo** depois de uma partida | O clarão do cano ficava **fora da árvore de cena** quando o personagem estava sem arma (ou ao trocar). Esse nó nunca era liberado e deixava uma instância no servidor de renderização depois que o mundo 3D sumia. Isolado por bissecção na build de release (modo remoto sem personagens: 4/4 limpos; local: travava). | O clarão é sempre filho do personagem e só acompanha o cano. Teste novo de encerramento (exit code) na bateria. Fumaça na release: exit 0. |
| Baú sem interação física | Abria sozinho. | Destaque pulsante, balão com tecla e anel de progresso, a mão alcançando a alça e acompanhando a tampa, partículas e som, itens saltando do baú e um jogador por vez. |

**Também incluído:** 22 efeitos sonoros originais sintetizados (tiros por categoria, recarga, baú, coleta, acerto, dano, escudo e cura) e o protocolo v3, com mira, item na mão e ação/progresso, para os outros jogadores verem as mesmas animações.

**Testado:**
- 63 unitários, incluindo 7 de construções com física real: subir piso e rampa nos 3 materiais, descer colado, não atravessar parede nem quina, telhado sólido e props.
- Fumaça: o tiro, o baú aberto pela interação e o IK ativo.
- Servidor dedicado com PvP.
- Capturas dentro do jogo de todas as situações: `game/tests/capturar_polimento.gd`.

**Ainda precisa de atenção:**
- A mira para cima/baixo dos outros jogadores é quantizada em 0,75°.
- Não há IK de pés em rampas (os pés podem afundar alguns centímetros na inclinação).
- O personagem remoto alcança o baú mais próximo, não necessariamente o exato.
- O custo de CPU do visual em celular não foi medido no aparelho.

### Etapa 3 — Traçantes visíveis (v0.3.2) ✅
| Problema | Causa | Correção |
|---|---|---|
| Rastro das balas quase invisível | Caixa fixa de 3 cm que piscava por 0,09 s; mistura aditiva que some contra o céu claro; saía do ombro, e não do cano; sem impacto. | Traçante que **viaja** a 190 m/s do **cano** até o alvo: faixa voltada para a câmera, cabeça brilhante, cauda que esmaece e largura que cresce com a distância. Mistura com transparência (âmbar com miolo branco) e rastro curto que some em 0,28 s. **Impactos:** faíscas e clarão no cenário, vermelho no jogador. A previsão local para o traçante no inimigo. |
| Faixa torta (ia para o lado do alvo) — achado na verificação | `Basis.scaled()` escala nos eixos do mundo. | Escala no eixo local (`base * Basis.from_scale`). |

**Verificado** com capturas dentro do jogo (`game/tests/capturar_tracantes.gd`): rifle nos bonecos, alvo a 25 m, leque da espingarda com impactos e vista lateral saindo do cano.

### Etapa 3 — Preparação final: picareta e inventário completo (v0.3.3) ✅
**Diagnóstico antes de implementar:** já existiam os 5 espaços, a munição separada com máximo, as pilhas de consumíveis, os baús e o loot, o ItemRig com IK e as miniaturas. Faltavam a picareta (nada existia), as operações de inventário pedidas pelo cliente (não havia mensagem para isso), a tela de inventário e o material do que é atingido. A coleta com inventário cheio **trocava em silêncio** pelo item selecionado (corrigido). Nada foi refeito: tudo foi construído sobre `Inventory`, `LootServer`, `CombatServer`, `ItemRig`, `ItemSlot` e `CombatFx`.

**Implementado:**
- **Picareta permanente** (`picareta_01`, modelo original de 532 triângulos, pelo pipeline: gerador Blender → `export_glb.py` → `validate_glb.py` → catálogo → importação na Godot). Fica no 1º espaço à esquerda da barra (picareta → 1 → 2 → 3 → 4 → 5), não ocupa espaço, não é largada, trocada nem perdida ao morrer, e é o item inicial de todo jogador. Seleção por F, ► no controle, toque no espaço e no ciclo da roda/LB-RB.
- **Animações** no ItemRig e no IK existentes (sem segundo sistema): segurar, correr, sacar e guardar (por cima do ombro), golpe A (de cima, na diagonal) e golpe B (horizontal), que se alternam nos golpes seguidos, com o tronco acompanhando. A troca de **qualquer** item agora guarda o anterior antes de sacar o próximo.
- **Golpe no servidor:** impacto num quadro definido (passo 8 de 19), um único impacto por golpe, alcance e cadência validados, material (madeira, pedra, metal ou terra), 20 de dano em jogadores e bonecos, previsão no cliente e confirmação para todos (`S_MELEE`). Os outros jogadores veem a picareta e o golpe.
- **Efeitos:** lascas, poeira ou faíscas por material, clarão no impacto e 9 sons novos sintetizados: corte de ar, impactos em madeira, pedra, metal e terra, sacar, largar, erro e mover.
- **Inventário completo e autoritativo:**
  - tela própria (Tab / Select / botão Mochila no toque) com os 5 espaços, a picareta, munição, materiais, itens próximos e detalhes do item;
  - mover (arrastar, ou "Mover" e o destino), dividir e largar com escolha de quantidade, pegar e substituir escolhendo o espaço;
  - limites de pilha vindos dos dados; o item largado vira loot para todos;
  - inventário cheio avisa e nunca troca nem pega em silêncio;
  - protocolo v4 (`C_INV`, `S_INV_RESULT`, `S_MELEE`, picareta na seleção e materiais no status).
- **Preparado para a Etapa 5, sem sistema provisório:** o sinal `melee_hit` no servidor, `dano_construcao`/`recursos_por_golpe` nos dados e os materiais já no inventário e no status.

**Testado (executado):**
- 84 unitários (21 novos): picareta permanente; troca e seleção; limites de pilha; coleta parcial sem perda; substituição explícita; divisão; largar quantidades; conservação; protocolo v4. Com o mapa real: impacto no quadro certo, um por golpe, cadência, madeira/pedra/metal, fora de alcance, boneco, operações recusadas e picareta ao morrer.
- Fumaça (pela rede): seleção dedicada, destaque no 1º espaço, golpe com impacto previsto e confirmado (3 de 3), **jogador remoto visto com a picareta golpeando**, abrir e fechar a tela, largar, recusar a picareta e pegar de volta pela lista de próximos.
- Servidor dedicado com 2 clientes, encerramento limpo (exit 0) e desempenho do servidor: 24 jogadores a 0,96 ms/tick (antes ~1,0).
- Capturas: `game/tests/capturar_picareta.gd` (fases do golpe, impactos por material, barra e tela de inventário).
- Benchmark visual (`perf_visual`, 16 personagens, agora com a picareta golpeando): 6,90 ms por quadro, **igual à v0.3.2**. Esse valor é o limite de quadros do modo headless, então o método só mostra que não houve regressão grande. A medição real é no seu notebook.

**Pendente / não validado:**
- Teste em hardware real (notebook e celular) e uso com controle físico (a navegação por foco foi feita, mas não testada com um controle de verdade).
- Vida das construções, rachaduras, destruição e coleta: Etapa 5 (ver abaixo).

### Etapa 4 — Mapa e sistemas Battle Royale ✅ (v0.4.0; falta a medição no seu hardware)
Começou automaticamente depois da picareta e do inventário validados, como pedido.

**Implementado:**
- **Mapa genérico** (`Mapa`): o servidor anuncia o mapa e o cliente o monta. Servidor, loot e cliente deixaram de depender do campo de treino.
- **Ilha Ventania** (~600 m, área jogável de 524 m): relevo determinístico (igual no servidor e no cliente), praias e mar, morro central.
  - 6 POIs originais feitos com as peças do kit: Vila Brisa, Pedreira Cinza, Porto Ferrugem, Fazenda Girassol, Mirante do Vento e Acampamento Coral.
  - 12 cabanas espalhadas, ~365 árvores, pedras e arbustos.
  - 37 baús e 102 pontos de loot.
  - Desenhada com MultiMesh por região e colisão com formas compartilhadas.
- **Loot pelo inventário novo:** baús e chão usam o mesmo `LootServer`/`Inventory` da v0.3.3 (pegar, trocar, largar). O loot é sorteado de novo a cada partida, e os baús não reabastecem no BR.
- **Partida (`PartidaBR`):**
  - espera (Mirante, sem dano), contagem, jogo, fim e nova partida;
  - cada jogador aparece num ponto da ilha só com a picareta;
  - eliminação definitiva com colocação e tela de resultado;
  - espectador (segue quem eliminou; Atirar troca, Esc volta ao menu);
  - vitória do último vivo (sozinho: sobreviver à Tormenta);
  - desconectar conta como eliminação; quem entra no meio assiste.
- **Tormenta:** 7 fases em `data/partida.json`, zona seguinte sempre dentro da atual e em terra, dano só na vida, desempate quando todos morreriam juntos. Parede roxa animada, aviso e tela roxa dentro dela, tempo e fase no HUD.
- **HUD da partida:** vivos/total, fase e tempo, minimapa gerado do relevo e mapa completo (M) com os POIs e as zonas atual e próxima.
- **Servidor dedicado:** roda partidas BR seguidas por padrão (`--modo=treino` para o campo, `--min-jogadores`, `--config`). No menu: **Battle Royale: Ilha Ventania** (local) e **Campo de treino**.
- **Protocolo v5:** `S_MATCH`, `S_STORM`, `S_RESULT` e material no loot.

**Aceite — executado:**
- **Partida completa com clientes simulados**, nos dois modos:
  - no processo, 6 clientes por ENet: espera → contagem → jogo → fim → nova partida; 5 de 6 pegaram arma, atiraram e eliminaram; vencedor único; colocações 1–6 sem repetição; todos receberam o resultado; a Tormenta fechou;
  - num **servidor dedicado em outro processo**, 4 clientes: partida completa com vencedor e colocações 1–4.
  Os clientes simulados (`tests/integration/cliente_simulado.gd`) jogam só com o que o servidor envia; não são os bots da Etapa 6.
- 90 unitários (6 novos: fases e zonas aninhadas em 5 sementes, fechamento, dano só na vida, mensagens, ilha determinística, mapa pelo nome). Fumaça do BR local: mapa vindo do servidor, contagem, início só com a picareta, Tormenta, HUD, loot, fim e resultado.
- **Benchmark do mapa nos 3 perfis** (`--benchmark-ilha` ou botão na tela de desempenho): rota pelos POIs com 16 personagens e a Tormenta. Aqui só há renderização por software (llvmpipe, sem GPU), então **o FPS daqui não vale para o seu aparelho**. As chamadas de desenho e primitivas não dependem da GPU:

| Perfil | Draw calls | Primitivas | Orçamento (ARCHITECTURE §9) | FPS no llvmpipe (só referência) |
|---|---|---|---|---|
| Desempenho | 73 | 57 mil | ≤ 150 / ≤ 100 mil | 26,4 (1% pior 18,9) |
| Equilibrado | 161 | 127 mil | ≤ 300 / ≤ 250 mil | 16,4 (12,4) |
| Qualidade | 191 | 158 mil | ≤ 600 / ≤ 600 mil | 7,7 (5,3) |

- **Servidor:** 24 jogadores na ilha a 3,8 ms/tick em média (11% do tick; picos de até 19 ms), contra 1,0 ms no campo de treino. O custo vem do relevo e dos ~760 corpos de colisão. Cabe no orçamento, mas é o primeiro ponto a otimizar se o PC do servidor for fraco.
- Capturas: `game/tests/capturar_ilha.gd` (vista aérea, os 6 POIs, chão, Tormenta, mapa e resultado).

**Pendente / não validado:**
- **FPS do mapa no seu notebook e no celular:** rode o Benchmark da Ilha e me mande o resultado. É o último item do aceite.
- Partida com pessoas de verdade pela rede (só clientes simulados até agora).
- As construções do mapa ainda não são destrutíveis (Etapa 5). Não há ônibus nem paraquedas (não fazia parte do plano da Etapa 4). Os bots (IA) são a Etapa 6.

### Etapa 5 — Construção ⬜
Parede, piso, rampa e teto, com grade, edição, destruição, desabamento sem apoio e materiais, tudo sincronizado.
**Requisitos registrados na preparação da picareta (v0.3.3):**
- vida individual por peça de construção;
- dano progressivo da picareta (`dano_construcao` em `itens.json`);
- feedback de deterioração e rachaduras progressivas;
- efeitos de impacto por material (a base já existe);
- fragmentos e partículas na destruição, e destruição completa com vida zero;
- deterioração e destruição sincronizadas entre jogadores;
- coleta de materiais na destruição e por golpe (`recursos_por_golpe`) e integração ao inventário (os materiais já existem lá).
- O ponto de ligação é o sinal `GameServer.melee_hit`.
**Aceite:** testes de grade e conectividade, 2 clientes construindo e editando sem divergência, e o limite de peças medido.

### Etapa 6 — Inteligência artificial ⬜
Navegação, exploração, saque, coleta, combate, cura, fuga da Tormenta e dificuldades, com LOD de IA.
**Aceite:** a simulação headless com 23 bots termina a partida sem travar, há métricas por dificuldade, e o custo de CPU por bot fica medido.

### Etapa 7 — Multiplayer e servidores ⬜
Servidor dedicado (export headless), salas, reconexão, validação e antimanipulação, relevância (interest management) e testes de banda e latência simulada.
**Aceite:** 2 PCs e 1 Android na mesma partida com bots, a reconexão funciona, e o uso de banda por cliente fica medido.

### Etapa 8 — Lobby e social ⬜
Login, identidade, lobby com o personagem em destaque, grupos, amigos, convites, seleção de modo, matchmaking com bots, sala privada e entrada na partida.

### Etapa 9 — Inventário e progressão ⬜
Inventário persistente, nível, XP, missões, recompensas, Faíscas (com ledger) e histórico de desbloqueios, tudo validado pelo servidor.

### Etapa 10 — Passe de batalha ⬜
Temporadas via JSON, níveis, interface de progressão, recompensas gratuitas, desafios e ferramenta de validação de temporadas.

### Etapa 11 — Loja rotativa ⬜
Catálogo, categorias, preços, pré-visualização, compra atômica, temporizador, rotação (agenda e sorteio determinístico) e uma ferramenta de administração do catálogo.

### Etapa 12 — Polimento e distribuição ⬜
UI final, áudio, animações, otimizações, tratamento de erros, testes multiplayer, exportações para Android, Windows e Linux, e o guia de instalação e de hospedagem para os amigos.

## Riscos conhecidos

| Risco | Impacto | Mitigação |
|---|---|---|
| Não há dispositivo Android nem GPU no ambiente de desenvolvimento | O desempenho real é desconhecido | Builds de teste para o grupo a partir da Etapa 2, com um benchmark que gera CSV |
| Hospedagem atrás de NAT | Amigos não conseguem conectar | VPN mesh, redirecionamento de portas ou VPS (ARCHITECTURE §13) |
| Escopo grande para um projeto pessoal | Sistemas pela metade | Marcos M1, M2 e M3, e nenhuma etapa avança sem aceite |
| Assets originais exigem produção artística | Visual simples por muito tempo | Placeholders geométricos originais primeiro e assets CC0 verificados depois |
| Contêiner de desenvolvimento efêmero | Perda de trabalho | Repositório git remoto antes da Etapa 1 |
