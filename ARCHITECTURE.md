# Arquitetura — Projeto Ventania

Versão do documento: 0.1 (Etapa 0). As decisões marcadas **[ADR-n]** estão
justificadas na seção 12.

## 1. Diagnóstico do ambiente (Etapa 0)

| Item | Resultado |
|---|---|
| Arquivos existentes no projeto | **Nenhum.** O diretório estava vazio e não era um repositório git. Nada a preservar ou migrar. |
| Engine instalada | Nenhuma. A versão estável mais recente encontrada foi o Godot **4.7.2-stable** (4.8 ainda não existe). Ela foi baixada e testada em modo headless: `4.7.2.stable.official.ed1daf0bf`. |
| Rede ENet | Validada: um servidor e um cliente ENet conectaram em loopback com o Godot 4.7.2 headless. |
| Templates de exportação | Disponíveis para download (`Godot_v4.7.2-stable_export_templates.tpz`). |
| Python | 3.13 no ambiente de desenvolvimento. O alvo mínimo do backend é 3.11. |
| Java | Presente. O Android SDK não está instalado. Ele só é necessário na Etapa 12 (ou antes, para os testes de desempenho em Android da Etapa 2). |
| Dependências de terceiros | Nenhuma no momento. A meta é zero até a Etapa 12, salvo justificativa. |

**Riscos do ambiente:** o contêiner de desenvolvimento é efêmero. O código precisa
ir para um repositório git remoto antes da Etapa 1. Não há GPU nem dispositivo
Android aqui. O desempenho real precisa ser medido em hardware do grupo (seção 9).

## 2. Visão de processos

```
 ┌───────────────┐   HTTP/JSON (login, loja, passe,   ┌─────────────────────┐
 │ Cliente Godot │◄── amigos, grupo, matchmaking) ───►│ Meta-servidor       │
 │ PC / Android  │    + long-poll de eventos          │ Python stdlib       │
 └──────┬────────┘                                    │ SQLite (WAL)        │
        │ ENet/UDP (gameplay)                         └───┬─────────▲───────┘
        │ ticket de partida assinado                      │ inicia  │ resultado
        ▼                                                 ▼ processo│ (HMAC)
 ┌──────────────────────────────────────────────────────────────────┴──┐
 │ Servidor de partida — Godot headless (1 processo por partida)       │
 │ simulação autoritativa, bots, tempestade, construção, loot          │
 └─────────────────────────────────────────────────────────────────────┘
```

- **Cliente:** renderização, entrada, UI, predição local e interpolação. Ele não decide nada importante.
- **Servidor de partida:** a fonte da verdade *durante* a partida (dano, inventário da partida, construção, eliminações, vencedor).
- **Meta-servidor:** a fonte da verdade *persistente* (conta, moeda, cosméticos, XP, passe, missões, loja, amigos, grupos). **[ADR-3]**
- Os processos rodam separados. O meta-servidor e os servidores de partida podem rodar na mesma máquina (o PC de um amigo ou uma VPS barata) ou em máquinas diferentes.

## 3. Projeto Godot único, dois papéis **[ADR-2]**

Um único projeto em `game/` gera:
- **Cliente:** exportações Windows, Linux e Android.
- **Servidor dedicado:** exportação Linux/Windows com a feature tag `dedicated_server` e o export mode "Dedicated Server". Esse modo remove texturas e áudio do pacote.

O código de gameplay é compartilhado. O papel é decidido na inicialização (`OS.has_feature("dedicated_server")` ou o argumento `--server`). O modo "listen/local" (servidor e cliente no mesmo processo, via loopback) é usado para desenvolvimento e para o treino solo com bots.

### Estrutura de diretórios do `game/` (implementada na Etapa 1)

```
game/
├── project.godot
├── autoload/            Singletons mínimos: Config, Log, SceneManager, Net, Audio, InputMap helpers
├── core/                Configurações, salvamento local, carregamento de recursos, utilitários
├── net/                 Protocolo, cliente/servidor ENet, snapshots, cliente HTTP do meta-servidor
├── gameplay/
│   ├── character/       Controlador, câmera, animação
│   ├── weapons/         Dados e lógica de armas (dados em .tres)
│   ├── items/           Consumíveis, munição, loot tables
│   ├── building/        Grade, peças, edição, dano estrutural
│   ├── match/           Fases da partida, tempestade, eliminações, vitória
│   └── world/           Mapa, baús, pontos de spawn
├── ai/                  Bots (percepção, decisão, ações)
├── ui/
│   ├── shared/          Tema, componentes e widgets reutilizáveis
│   ├── pc/              Layouts para teclado/mouse/controle
│   └── mobile/          Layouts touch (não é o PC redimensionado)
├── cosmetics/           Apresentação visual dos cosméticos (sem lógica de gameplay)
├── assets/              Modelos, texturas, áudio, fontes (cada pasta com LICENSES.json)
└── tests/               Runner de testes próprio + testes unitários e de simulação
```

Regra: um sistema por pasta, arquivos pequenos e sem "god objects". Os autoloads
apenas coordenam. A lógica fica em classes testáveis.

### Convenções de código (Etapa 1)

- **Autoloads, em ordem:** `Log`, `Audio`, `Settings`, `InputManager`, `Meta`, `SceneManager`. A ordem importa: `Settings` aplica volumes no `Audio`.
- **Lógica testável fica em classes `RefCounted` sem dependência de cena** (`SettingsStore`, `SettingsSchema`, `InputSerializer`, `PlayerProfile`, `Benchmark`, `SafeFile`). Os autoloads só aplicam e coordenam.
- **O mundo se integra às configurações por grupos:** `sol` (DirectionalLight3D), `camera_principal` (Camera3D) e `ambiente` (WorldEnvironment).
- **Nomes de API em inglês** (`get_value`, `go`, `check_health`). Comentários, textos de interface e variáveis locais em português.
- **Scripts executados com `-s`** (testes) não enxergam os autoloads como identificadores. Use `root.get_node("Settings")`, ou rode o jogo com `-- --teste-fumaca`.

## 4. Rede em partida **[ADR-4]**

- **Transporte:** `ENetMultiplayerPeer`, UDP, com canais separados (confiável para eventos, não confiável e sequenciado para snapshots/entrada).
- **Modelo:** servidor autoritativo com tick fixo de **30 Hz** de simulação e envio de snapshots a **20 Hz** (ajustável).
- **Jogador local:** envia *entrada* (não posição) numerada. O cliente prediz o movimento localmente e reconcilia quando chega o estado do servidor.
- **Outros jogadores e bots:** interpolação com buffer de cerca de 100 ms.
- **Tiros:** hitscan validado no servidor com compensação de latência limitada (rewind de no máximo 200 ms) e checagem de linha de visão e de cadência. O cliente só mostra efeitos.
- **Serialização:** pacotes binários compactos (`PackedByteArray` / `StreamPeerBuffer`) para snapshots, com delta contra o último snapshot confirmado. RPCs do Godot só para eventos raros. `MultiplayerSynchronizer` não é usado para entidades em massa, por causa do custo de banda e CPU.
- **Relevância (interest management):** cada cliente recebe as entidades dentro de um raio e da área de visão. Entidades distantes são enviadas com menos frequência.
- **Construção:** sincronizada como eventos (`colocar`, `editar`, `danificar`, `destruir`) sobre uma grade, não como nós replicados. Quem entra no meio da partida recebe um snapshot compacto da grade.
- **Reconexão:** quando um jogador cai, o servidor mantém o personagem dele por até 60 s (configurável). O cliente reconecta com o mesmo ticket e recebe o estado completo.
- **Versão:** o handshake envia `protocol_version` e `content_version`. Se forem incompatíveis, o servidor recusa com uma mensagem clara ("atualize o jogo").

> **Problema arquitetural sinalizado:** o roteiro original deixa o multiplayer para
> a Etapa 7, depois do gameplay, da construção e dos bots. Adaptar rede depois a
> um jogo feito para um jogador só é a causa mais comum de reescritas. **Decisão
> proposta:** desde a Etapa 2, todo o gameplay roda pelo caminho
> cliente → servidor → cliente, mesmo localmente (servidor em processo, via
> loopback). A Etapa 7 passa a cuidar do servidor dedicado, das salas, da
> reconexão, do endurecimento e dos testes com vários clientes, em vez de "adicionar
> rede". Veja o ROADMAP.

### 4.1 Como a rede ficou na Etapa 2 (implementado e medido)

| Item | Implementação |
|---|---|
| Arquivos | `net/protocol.gd` (formato binário), `net/game_server.gd`, `net/game_client.gd`, `scenes/game/game.gd` (predição/interpolação), `gameplay/character/movement.gd` (simulação compartilhada) |
| Tick e snapshots | Física a 30 Hz com interpolação visual nativa da Godot; snapshot a cada 2 ticks (15 Hz) |
| Entradas | Cada pacote leva as 3 últimas entradas (perda de pacote). O servidor processa **uma entrada por passo, na ordem**, espera até 6 ticks por uma entrada atrasada e recupera com até 2 por tick. Fila máxima de 8 (protege contra speed hack). |
| Predição | O cliente aplica `Movement.step` com a mesma entrada que envia. No snapshot: aplica o estado do servidor (posição, velocidade, agachado, no chão) e reaplica as entradas ainda não confirmadas. |
| Determinismo | O snap ao chão é manual e só depende de `Pawn.grounded`, que viaja no snapshot; o snap nativo do CharacterBody3D fica desligado. Jogadores não colidem entre si. |
| ENet | `bandwidth_limit(0, 0)` nos dois hosts e throttle por conexão desligado. Sem isso, os pacotes não confiáveis caíam para ~1/32 depois de 1 s (medido). |
| Mundo do servidor local | `SubViewport` com `own_world_3d` e renderização desligada: espaço físico separado do cliente no mesmo processo. |
| Servidor dedicado | O mesmo executável com `--headless -- --servidor [--porta=24800]`. |
| Custo medido | 24 jogadores: ~1 ms por tick de servidor (3% de 33 ms). Snapshot de 16 jogadores: ~470 bytes. |

### 4.2 Visual do personagem (polimento da Etapa 3)
Ordem por quadro:
1. **AnimationTree:** locomoção em BlendSpace1D sincronizado, agachado, pulo/queda e aterrissagem em one-shot.
2. **AimPoseModifier:** coluna, peito, pescoço e cabeça seguem a mira.
3. **ItemRig:** item na pose da categoria mais as ações procedurais; define os alvos das mãos a partir dos marcadores do modelo.
4. **TwoBoneIK3D** em cada braço.

O item comanda as mãos, nunca o contrário. Os marcadores ficam nos modelos (`grip_r`, `grip_l`, `muzzle`, `mag`, `mao`, `alca_tampa`).

**Padrões da grade de construção** (gerador `gerar_construcoes.py`, teste `test_construcoes.gd`):
- piso com topo a 0,10 m;
- parede de 0,24 m;
- rampa do topo de um piso ao topo do próximo;
- telhado em pirâmide de 1,6 m;
- colisões convexas iguais ao visual.

### 4.3 Picareta e inventário (preparação final da Etapa 3, protocolo v4)
- **Picareta permanente:** não é um item de espaço. O `Inventory` tem um espaço fixo interno (`selected = Inventory.PICKAXE`), e nenhuma operação a aceita: largar, trocar de posição, dividir, guardar num espaço ou cair ao morrer (`drop_all` só esvazia os 5 espaços e volta a seleção para ela). Todo jogador começa com ela na mão. Seleção: `InputCmd.slot = 6` (`SLOT_PICKAXE`); no status, `selected = 255`.
- **Golpe:** decidido no servidor, no relógio de passos do jogador (`simulados`), igual ao tiro. Duração `Combat.melee_swing_steps()` (19 passos) e impacto em `melee_impact_step()` (8): um único raio da mira até 2,4 m, contra o cenário (física) e contra jogadores/bonecos (hitbox voltada no tempo). **No máximo um impacto por golpe** (`swing_hit`), e a cadência é validada pelo servidor. Golpes seguidos alternam o lado (`ACT_SWING`/`ACT_SWING_B` no snapshot, com o progresso). O cliente prevê o mesmo relógio, anima e mostra o impacto na hora; o servidor confirma com `S_MELEE` (para todos, com material, posição e normal) e aplica dano a jogadores (`S_HIT`).
- **Material:** `ImpactMaterial` lê a meta `material` que o mapa grava no nó raiz de cada asset (madeira, pedra, metal, terra). Efeitos e sons dependem dele.
- **Gancho da Etapa 5:** `GameServer.melee_hit(player_id, collider, material, pos)` é emitido a cada impacto no cenário. Vida das peças, rachaduras, destruição e coleta vão se ligar aí; os dados (`dano_construcao`, `recursos_por_golpe`) já estão em `itens.json`. Nada disso está implementado ainda.
- **Inventário autoritativo:** o cliente pede operações por `C_INV` (canal confiável): trocar posições, dividir, largar (espaço, munição ou material, com quantidade) e pegar um item específico (com espaço a substituir). O servidor valida cada uma em `CombatServer.inventory_op` (alcance, limites, espaço livre, regras de descarte, até 12 operações/s) e responde `S_INV_RESULT` com um código (`Inventory.Err`). O estado novo vai sempre no `S_STATUS`; a interface nunca muda o inventário sozinha.
- **Sem perda nem duplicação:** o que sai do inventário volta ao chamador e vira loot; o que não coube continua no chão (a mesma entrada, com a quantidade atualizada). Inventário cheio **nunca troca em silêncio**: com Interagir, a troca é pelo item na mão (o aviso diz "Trocar X por Y"); com a picareta na mão, aparece "Inventário cheio". Testes de conservação somam itens no inventário e no chão antes e depois de cada operação.
- **Item largado:** cai 1,6 m à frente, no chão (raio para baixo), ou aos pés se houver parede no caminho. Quem largou não o recoleta automaticamente por 2 s.
- **Dados:** `itens.json` → `regras` por categoria (pilha, coleta, descartável), que cada item pode sobrescrever; `ferramentas.picareta`; `materiais` (madeira, pedra e metal, com máximo de 999, ainda sem forma de obter).

### 4.4 Partida Battle Royale (Etapa 4, protocolo v5)
- **Mapa genérico:** `Mapa` (base) define baús, pontos de loot, pontos de início, altura do chão, POIs, limite e altura de morte. `CampoTreino` e `IlhaVentania` herdam dele; o servidor anuncia o mapa no `S_WELCOME` e o cliente o cria com `Mapa.create(nome)`.
- **Ilha Ventania:** gerada de forma determinística pela semente (o mesmo relevo e a mesma colocação no servidor e no cliente, verificados em teste). Relevo de 201×201 amostras a cada 3 m, colisão `HeightMapShape3D` e visual em 8×8 blocos com corte por distância. Construções e vegetação passam pelo `KitInstancer`: um `StaticBody3D` por peça, com formas compartilhadas e meta `material`, e o visual em `MultiMeshInstance3D` por (malha, região de 100 m) com distância de visibilidade. Ficam ~760 corpos e ~190 grupos visuais; na tela, 73–191 chamadas de desenho conforme o perfil. As construções do mapa ainda não são destrutíveis: na Etapa 5 as peças precisam virar entidades com vida (a colocação já passa por um único ponto, `_peca`).
- **Regras (`PartidaBR`, só no servidor):** ESPERA (área do Mirante, sem dano, quem cai volta) → CONTAGEM → JOGO (loot sorteado de novo, jogadores espalhados nos pontos de início com o inventário vazio, Tormenta ativa, sem reaparecer) → FIM (vencedor) → nova partida. Quem entra no meio da partida assiste. A vitória vem quando sobra 1 jogador numa partida com 2 ou mais; sozinho, quando a última fase termina com o jogador vivo. Colocação = quantos estavam vivos na eliminação. Desconectar conta como eliminação.
- **Tormenta (`Tormenta`):** fases em `data/partida.json` (espera, fechamento, raio e dano). A próxima zona é sorteada dentro da atual (cabe inteira) e em terra. O dano é aplicado 1×/s só na vida (ignora o escudo). Se o dano eliminaria todos os que restam, o de mais vida sobrevive e vence.
- **Mensagens (v5):** `S_MATCH` (estado, vivos, total, tempo restante, vencedor; a cada mudança e 1×/s), `S_STORM` (círculos de/para e tempos; o cliente interpola o fechamento) e `S_RESULT` (colocação, eliminações e tempo vivo, para o próprio jogador). O loot ganhou o campo `mat` (materiais no chão).
- **Cliente:** `StormVisual` (parede roxa animada), `MatchHud` (estado, aviso e tela roxa na Tormenta, minimapa gerado do relevo, mapa completo com os POIs, espectador e resultado). O espectador segue o visual interpolado do jogador assistido (`PlayerCamera.alvo` aceita qualquer `Node3D`).

### 4.5 Construção (Etapa 5, protocolo v6)
- **`Grade`** (matemática pura, igual no servidor e no cliente): slots `Vector4i(tipo, cx, cy, cz)` numa grade de 4 m alinhada ao mundo, transformações dos assets do kit, arestas para conexões, ancoragem no terreno, ladrilhos de edição e escolha do slot pelo olhar.
- **`Construcoes`**: as peças e os índices por slot e por aresta. `unsupported()` faz uma busca em largura a partir dos vizinhos das peças removidas, parando ao encontrar uma âncora. O servidor e cada cliente têm uma cópia; `snapshot()` permite comparar as duas.
- **`BuildServer`**: valida pedidos, cria um StaticBody3D por peça (formas do kit compartilhadas ou caixas dos ladrilhos; metas `peca_id` e `material`), aplica dano de tiros e da picareta, coleta e desabamento em lotes. As peças do mapa vêm de `Mapa.building_pieces()` (ids 1..N determinísticos), e o cliente as gera sozinho: na rede só vão as diferenças.
- **`BuildClient`**: aplica as mensagens, mantém a colisão para a predição e desenha. As peças inteiras ficam em MultiMesh com `use_custom_data` (x = dano, y = obra, z = pintura da casa do mapa, w = "torto": envergadura suave só nas peças do mapa, desde a 1.3.0); o `toon_paleta.gdshader` desenha rachaduras (bordas de Voronoi que se alargam com o dano) e o tom de obra. Fora de MultiMesh com dados, esses valores são 0, e personagens e armas não mudam. As peças editadas são malhas de caixas por ladrilho.
- **`BuildMode`** (cliente): prévia, construção em sequência e edição. Só pede ao servidor; o `InputSampler` deixa de enviar Atirar/Mirar/Recarregar enquanto a construção está ativa.
- **Limite:** 1200 peças de jogadores (`data/construcao.json`), medido em `perf_construcao.gd` (ROADMAP, Etapa 5).

### 4.6 Bots (Etapa 6)
- Um bot é um `GameServer.Cliente` com `bot: BotCerebro` e `peer_id <= 0` (o `send_to` ignora). A cada tick, antes da simulação, o cérebro coloca um `InputCmd` na fila; a partir daí o caminho é o mesmo dos humanos: `Movement.step`, `CombatServer.process`, inventário, `BuildServer.try_build`, ônibus e queda. Nada do mundo é alterado diretamente pela IA.
- `BotCerebro`: utility scoring a 5 Hz (1 Hz longe de humanos), execução por tick. A percepção usa raios de visibilidade com orçamento global (`GameServer.bot_raios`, 24 por tick), e há ganchos de audição (`bots_hear`) e de dano (`on_damaged`).
- `NavGrade`: 150 × 150 células de 4 m com arestas bloqueadas por paredes (térreo, exceto portas), relevo e obstáculos grandes do mapa (`Mapa.nav_obstacles`). O `BuildServer` a atualiza em cada criação, edição e destruição. O A* tem limite de 6000 expansões e 2 caminhos por tick no total.
- Métricas por jogador em `Cliente.stats` (saques, curas, dano causado, dano da Tormenta, construções), gravadas no histórico da partida. O custo de CPU fica em `GameServer.tempo_bots_us` e `tempo_tick_us`.

### 4.7 Servidores, reconexão e relevância (Etapa 7, protocolo v8)
- **Ficha de sessão:** um u64 aleatório no WELCOME.
  - Na queda (ônibus/jogo), o `Cliente` muda para um `peer_id` negativo e fica parado; o servidor simula sem entradas.
  - O HELLO com a ficha reassocia o `Cliente` ao novo peer e reenvia o estado (`_estado_completo` + partida/Tormenta/ônibus).
  - Depois de `JANELA_RECONEXAO_S`, o `_sair` faz o normal: larga o inventário e avisa a partida.
  - `C_BYE` antes de fechar marca a saída voluntária. O ENet descarta pacotes que chegam depois da desconexão, por isso o `GameClient.close` entrega a conexão a um nó auxiliar que a desliga com `peer_disconnect_later`.
- **Limites por conexão:** pacotes por segundo (ignora acima de 240, expulsa acima de 900) e pacotes malformados (`_receber` retorna `false`; 40 expulsam). A expulsão manda o motivo e desconecta depois de entregar.
- **Relevância:** `GameServer.relevant(dist, eu, meia)` filtra cada snapshot por cliente; `broadcast_near` limita traçantes e golpes. No cliente, um remoto só some depois de ~1 s sem aparecer.
- **Salas:** `server_main.gd` cria N `GameServer` em `SubViewport`s com `own_world_3d`. A física e a navegação de cada sala são separadas.

## 5. Meta-servidor **[ADR-3]**

- Python 3.11+ e **somente a biblioteca padrão**: `asyncio` (servidor HTTP próprio e enxuto), `sqlite3`, `hashlib` (PBKDF2), `hmac`, `secrets`, `json`, `unittest`.
- **API:** HTTP/JSON versionada (`/v1/...`). As notificações (convite, grupo atualizado, partida encontrada) usam *long-polling* (`/v1/events`), que o `HTTPRequest` do Godot suporta em todas as plataformas. WebSocket fica como evolução opcional.
- **Persistência:** SQLite em modo WAL. Toda alteração de moeda ou inventário roda em **uma transação** e grava uma linha em um *ledger* (livro-razão) com uma chave de idempotência.
- **Configuração de conteúdo** (fonte da verdade, versionada no git):
  - `backend/config/catalog/*.json`: cosméticos (id, nome, descrição, imagem, raridade, categoria, preço base).
  - `backend/config/seasons/<id>.json`: temporada, níveis, XP, recompensas e desafios.
  - `backend/config/shop/*.json`: agenda de rotação (datas e itens fixos) e regras da rotação automática.
  - Os arquivos são validados por um script em `tools/` antes do servidor subir. Se a configuração for inválida, o servidor não inicia.
- **Responsabilidades:** contas e sessões, amigos e presença, grupos e convites, fila de matchmaking, criação de salas privadas, início e encerramento dos processos de partida, aplicação dos resultados (XP, missões, moeda), passe, loja e inventário.

### 5.1 Como ficou na Etapa 8
- **Módulos:**
  - `contas.py`: cadastro, login, sessões e limite de tentativas;
  - `social.py`: amigos no SQLite; grupos, convites, presença e eventos em memória (se o servidor reiniciar, cada um volta a ficar sozinho);
  - `partidas.py`: salas anunciadas por heartbeat, fila, reservas, tickets e sala privada.
- Uma tarefa de 1 s expira presença e convites e roda o casamento da fila.
- **Segredo dos servidores:** vem de `VENTANIA_SEGREDO`/`server_secret`; se não houver, é gerado na primeira execução, guardado no banco e mostrado no log.
- **Servidor de partida:** `MetaLink` manda o heartbeat (estado, humanos, contas presentes) e recebe as ordens "privada" e "começar".
  - `Ticket.verify` confere o HMAC, a porta e a validade.
  - A mesma conta voltando assume o personagem (usa a ficha de reconexão).
  - A marca `priv` no ticket faz a sala saber que é privada antes do próximo heartbeat.
- **Cliente:** o autoload `Meta` guarda a sessão em `user://session.cfg`, mantém o laço de long-polling e repassa sinais (grupo, amigos, convite, partida encontrada).
  - Se a sala se anunciou como `127.0.0.1` (mesmo PC do meta), o cliente usa o endereço do meta-servidor.

### 5.2 Progressão (Etapa 9)
- `progressao.py`: perfil (XP, nível, Faíscas, contadores), `ledger` (delta, saldo depois, motivo, `idem_key` única), `unlocks` (item, origem, data), `loadout` (espaço → item), `quest_progress` (conta, missão, período) e `match_reports`/`match_results`.
- Tudo de um relatório roda numa única transação `BEGIN IMMEDIATE`. Os eventos `progress` só saem depois do COMMIT.
- O servidor de partida (`PartidaBR._relatorio`) guarda a conta e as estatísticas de cada participante, inclusive de quem saiu depois de eliminado, e emite `GameServer.match_report`. Quem envia é o `MetaLink`.
- O cliente só lê (`/v1/profile`, `/v1/quests`, `/v1/ledger`, `/v1/history`) e só pede para equipar (`/v1/loadout`).

### 5.3 Passe de batalha (Etapa 10)
- Temporadas em `backend/config/seasons/*.json`, carregadas e validadas por `progressao.carregar_config` (inclui a checagem de visual dos trajes em `game/data/cosmeticos.json`).
- Progresso em `season_progress` (conta, temporada, XP, nível).
- `_subir_passe` roda na mesma transação do relatório. As recompensas usam as chaves `passe:<temporada>:<nível>:<conta>` (Faíscas) e a origem `passe:<temporada>:<nível>` (itens), então nada é entregue duas vezes.
- Os desafios da temporada reaproveitam `quest_progress`, com período = id da temporada.
- `/v1/season` devolve o passe pronto para a interface.

### 5.4 Loja (Etapa 11)
- `loja.py`:
  - rotação calculada, sem nada guardado: Destaques pela segunda-feira e Diária numa corrente determinística dos últimos 30 dias, para "não repetir ontem";
  - compra usa `Progressao._tx/_creditar/_desbloquear` (mesmo extrato e mesmo histórico de desbloqueios), com a chave `loja:<conta>:<chave do cliente>`.
- `tools/admin_loja.py` usa as mesmas funções do servidor (prever = exatamente o que o servidor vai mostrar).

## 6. Identidade, sessões e segurança

- **Conta:** nome de usuário e senha (PBKDF2-SHA256 com salt e 200k iterações). O token de sessão é aleatório e fica guardado no cliente. Não há e-mail nem dados pessoais.
- **Ticket de partida:** quando o matchmaking fecha uma partida, o meta-servidor emite tickets assinados com HMAC (contendo jogador, partida, expiração e cosméticos equipados). O servidor de partida valida o ticket sem confiar no cliente.
- **Resultado da partida:** o servidor de partida envia ao meta-servidor um relatório assinado com um segredo compartilhado (colocação, eliminações, tempo vivo, eventos de missão). **Só o meta-servidor** concede XP, moeda e recompensas, e cada relatório é aplicado uma única vez (idempotência por `match_id`).
- **Antimanipulação básica:** validação de velocidade e teleporte, cadência de tiro, munição e alcance, alcance de construção e de coleta, custo de materiais e limite de taxa nas RPCs. O cliente nunca envia "dano causado", "item obtido" nem "moeda ganha".
- **Compras:** feitas no servidor, de forma atômica (verifica saldo, verifica posse, verifica se o item está na loja *agora*, debita, concede e registra no ledger). **Não há pagamentos reais.**
- **Transporte:** a primeira versão usa HTTP em rede privada ou VPN. Se o servidor for exposto na internet, deve ficar atrás de TLS (proxy reverso com Let's Encrypt), o que está documentado como requisito para essa forma de hospedagem.

## 7. Dados do jogador

| Dado | Onde fica | Quem altera |
|---|---|---|
| Configurações gráficas, de controle e de áudio | Cliente (`user://settings.cfg`), por dispositivo | Cliente |
| Token de sessão | Cliente (`user://session.cfg`) | Meta-servidor emite |
| Conta, nível, XP, moeda, inventário, passe, missões, histórico de desbloqueios | Meta-servidor (SQLite) | Só o meta-servidor |
| Estado de uma partida (vida, armas, construções) | Memória do servidor de partida | Só o servidor de partida |

O cliente guarda apenas um *cache* de leitura do perfil, para exibir o lobby rapidamente.

## 8. Cosméticos separados do gameplay

- O gameplay só conhece o **esqueleto e as hitboxes padronizados**, iguais para todos os trajes. Assim nenhum cosmético muda o tamanho do alvo ou a visibilidade.
- Um cosmético é: `id` → recursos visuais (malha, material, ícone, animação de emote). O catálogo (metadados e preço) vem do servidor, e os recursos visuais vêm do pacote do cliente.
- Se o cliente não tiver o recurso de um id (versão antiga), ele usa um visual padrão.

### 8.1 Estrutura (Etapa 13)

| Peça | Onde | Papel |
|---|---|---|
| Catálogo | `backend/config/catalog/*.json` | id, nome, categoria, raridade, descrição (servidor = fonte da verdade). `progressao.py` recusa item sem visual no jogo |
| Tabela de visuais | `game/data/cosmeticos.json` | id → cena: `trajes`, `picaretas`, `planadores`, `efeitos` (ex.: aquário), `trajes_dos_bots` |
| Acesso | `Cosmeticos` (`outfit_scene`, `pickaxe_scene`, `glider_scene`, `valid_id`) | id desconhecido → padrão |
| Modelos | `tools/assets/kit/blender/gerar_skins.py` → `game/assets/personagens/`, `armas/`, `mochilas_acessorios/` | esqueleto padrão, skinning rígido por osso, até 3 materiais (`M_paleta_ventania`, `M_vidro_ventania`, `M_agua_ventania`) |
| Efeitos | `TrajeFx` (preso ao osso Head) | peixes, bolhas e água do aquário; só visual, com LOD de 30 m |
| Rede | ticket (`traje`, `pic`, `plan`) → `GameServer` valida → `pack_player_info` (protocolo 11) → `game.gd` cria o `PawnVisual` | nenhum quadro a quadro: os outros jogadores recebem os ids uma vez |
| Imagens | `game/tests/gerar_imagens_loja.gd` → `game/assets/ui/loja/<id>.png` | renderizadas do modelo real; regenerar ao mudar um modelo |
| Visualizador | `VitrineCosmetico` (`game/ui/shared/`) | modelo real em SubViewport, arrastar para girar, enquadramentos |

**Garantia de "só aparência":**
- o servidor guarda `picareta` e `planador` no `Cliente` só para repassá-los no `player_info`;
- dano, coleta, velocidade de queda, planeio e hitbox não leem esses campos;
- `test_picareta_cosmetica.gd` confere isso numa partida real.

### 8.2 IA e navegação (revisão)

- **`NavGrade`** (`gameplay/ai/nav_grade.gd`):
  - nós do chão (150 × 150 células de 4 m) mais nós de andar, um por peça de piso a mais de 2,5 m do relevo;
  - ligações entre níveis com pontos de passagem: escadas (`Mapa.stairs()`) e rampas (`Grade.RAMPA`, do mapa e construídas);
  - `set_piece()` é chamado pelo `BuildServer` a cada peça que surge ou some;
  - portas são pontos de passagem exatos;
  - encostas acima de 40° (3,4 m em 4 m) são bloqueadas;
  - obstáculos: círculos (rochas) e retângulos (contêineres);
  - `path3(de, para, evitar)` devolve pontos 3D, a marca "preciso" e os nós.
  - Por que não NavigationServer3D: assar uma navmesh de 600 m custa segundos no servidor e teria de ser refeita a cada construção.
- **`BotCerebro`:**
  - decide por utility scoring com inércia de estado e compromisso mínimo ao recuar;
  - executa por estado;
  - tem o monitor de progresso e a recuperação (manobra → evitar aresta → abandonar alvo);
  - percepção com memória; cobertura por raycast do inimigo;
  - parâmetros por dificuldade em `data/bots.json`.
- **Custo** (`test_bots`, 23 bots, partida completa, física do jogo): cerca de 0,04 ms por bot por tick, tick médio de 4,8 ms de 33 ms.
  - Orçamentos por tick: 24 raios de percepção e 2 A*.
  - Decisões escalonadas e a 1 Hz longe de humanos.
- **Testes de bots e navegação** rodam com `--fixed-fps 30`: simulação na velocidade máxima com o passo do jogo. `time_scale` distorcia a física (passo de 0,13 s).

### 8.3 Interiores e mapa

- Escadas e mobília são props do `KitInstancer`:
  - colisão por formas convexas compartilhadas;
  - visual em MultiMesh por região;
  - distância de visibilidade e sombra vêm do próprio asset (mobília: 40 m, sem sombra).
- A mobília é gerada por `IlhaVentania._mobiliar()` com gerador próprio, determinístico (igual no servidor e no cliente), e não entra na rede.
- Regiões do mapa: `IlhaVentania.POIS` é a fonte única; `region_bounds()` deriva o contorno das áreas ocupadas por cada POI.

## 9. Desempenho e hardware

**Revisão de qualidade (v1.2.0):**
- Medido antes de otimizar (`tests/perf/perf_categorias.gd`): as construções eram 2/3 das chamadas de desenho, porque as paredes com janela/porta viravam até 9 ladrilhos mais molduras, cada um num MultiMesh.
- Correção: uma malha por (tipo, material, máscara), em cache. Na vista da vila, as construções passaram de 219 para 86 chamadas.
  - Os ladrilhos recortados não são indexados e as molduras são. A moldura é desindexada antes de juntar; misturar os dois fazia o SurfaceTool perder os ladrilhos (bug da 1.2.0, corrigido na 1.2.1).
- Perfis Baixo/Médio/Alto ganharam "Detalhes do cenário": distância de detalhe, densidade da vegetação decorativa sem colisão e partículas.
- Benchmark `tests/perf/bench_mapa.gd`, por fora e por dentro dos edifícios: números no ROADMAP (revisão de qualidade).


**Renderizador: Compatibility** (OpenGL ES 3.0 / OpenGL 3.3). **[ADR-1]**

Orçamentos iniciais, a revisar com medições na Etapa 2:

| Métrica | Performance (mobile modesto) | Balanced | Quality |
|---|---|---|---|
| FPS alvo | 30 | 60 (PC) / 30 (mobile) | 60 |
| Draw calls na tela | ≤ 150 | ≤ 300 | ≤ 600 |
| Triângulos na tela | ≤ 100k | ≤ 250k | ≤ 600k |
| Resolução 3D (escala) | 0,6–0,75 | 0,85 | 1,0 |
| Sombras | Desligadas ou blob | 1 cascata, baixa | 2 cascatas |
| Distância de visão | Curta + neblina | Média | Longa |
| RAM total (Android) | ≤ 700 MB | ≤ 1 GB | — |

Técnicas planejadas:
- **LOD:** `visibility_range` dos nós e LOD automático de malhas do Godot.
- **Culling:** frustum culling (nativo), visibility range e occlusion culling com `OccluderInstance3D` só nas áreas densas, se a medição justificar.
- **Draw calls:** `MultiMeshInstance3D` para vegetação, peças de construção e props repetidos, além de atlas de textura e poucos materiais compartilhados.
- **Texturas:** compressão VRAM (S3TC/BPTC no PC, ETC2/ASTC no Android), mipmaps e tamanho máximo por perfil.
- **Iluminação:** uma luz direcional, ambiente simples, sem GI em tempo real e sem pós-processamento caro.
- **Partículas e entidades:** limites globais por perfil, com pools de objetos (projéteis, efeitos, pickups).
- **Servidor:** física e IA com LOD (bots longe dos humanos tomam decisões em frequência menor), navmesh pré-calculada e sem renderização.

Todas as opções são independentes. Os perfis só preenchem os valores, e o
jogador pode ajustar cada um.

## 10. Configurações por plataforma

- Os padrões por plataforma usam feature tags (`mobile`, `pc`, `android`) e arquivos `res://core/settings/defaults_<plataforma>.cfg`.
- As preferências do jogador ficam em `user://` e sobrescrevem os padrões.
- A UI tem layouts separados em `ui/pc/` e `ui/mobile/`, que compartilham tema e componentes. Os controles touch podem ser reposicionados e redimensionados, com o layout salvo localmente.

## 11. Testes e validação

- **Godot:** um runner próprio e mínimo (`tests/run_tests.gd`, executado com `godot --headless -s`) para evitar dependência de addons. O GUT pode ser avaliado depois, se o runner ficar limitado.
- **Simulação:** cenários headless com N bots e sem clientes (validam IA, tempestade e fim de partida) e com clientes headless simulados (validam rede).
- **Backend:** `unittest`, cobrindo transações, idempotência, rotação da loja, progressão do passe e validação de configs.
- **Desempenho:** cena de benchmark com câmera em trajeto fixo, registrando FPS, draw calls e memória (via `Performance`) em CSV.
- **CI** (quando houver repositório remoto): testes headless, validação de configs e da licença de assets.

## 12. Registro de decisões (ADR)

**ADR-1: renderizador Compatibility.** Os renderizadores Forward+ e Mobile exigem
Vulkan, D3D12 ou Metal. Muitos Android de 2–3 GB e GPUs integradas antigas não
têm Vulkan estável. O Compatibility roda em OpenGL ES 3 / GL 3.3, tem a maior base
de hardware, e o estilo cartunesco não depende de recursos avançados. *Custo:* sem
SDFGI, VoxelGI e alguns efeitos, o que é aceitável para a direção visual.

**ADR-2: um projeto Godot para cliente e servidor de partida.** A simulação
compartilhada evita divergências entre o cliente que prediz e o servidor que decide.
A exportação de servidor dedicado remove os assets pesados. *Alternativa
rejeitada:* um servidor de partida em outra linguagem, que duplicaria física,
armas e construção.

**ADR-3: meta-servidor em Python stdlib + SQLite.** Moeda, compras e recompensas
exigem transações ACID. O Godot não tem banco de dados embutido (seria preciso o
GDExtension godot-sqlite, uma dependência binária por plataforma) nem servidor
HTTP pronto. O Python com a biblioteca padrão oferece `sqlite3` transacional,
`asyncio` e criptografia sem nenhum pacote externo, e roda em qualquer PC ou VPS.
*Alternativas consideradas:* um backend em Godot (com arquivos JSON ou um addon de
SQLite) e Node, Go ou FastAPI (mais dependências ou mais uma toolchain). *Custo:*
duas linguagens no repositório, mitigado por um protocolo JSON documentado e
pelos testes.

**ADR-4: ENet com snapshots próprios.** O ENet vem embutido no Godot, usa UDP com
canais confiáveis e não confiáveis e funciona em PC e Android. WebSocket ou WebRTC
só seriam necessários para um cliente web, que não é alvo. Os snapshots próprios,
em vez de `MultiplayerSynchronizer`, dão controle sobre banda, delta e relevância,
o que é essencial para 24–32 entidades e construções.

**ADR-5: tamanho de partida inicial.** O alvo inicial é de **até 24 participantes**
(humanos e bots) no mapa pequeno, depois 32 a 50 se as medições permitirem.
Partidas de 100 jogadores não são meta: o servidor roda no PC de um amigo ou em
uma VPS barata, e o grupo é pequeno.

## 13. Hospedagem para o grupo de amigos (planejamento)

Uma máquina roda o meta-servidor e os servidores de partida. As opções, em ordem
de simplicidade:
1. **VPN mesh** (Tailscale, ZeroTier ou similar) entre os amigos: sem abrir portas e já criptografada.
2. **Redirecionamento de portas** no roteador de quem hospeda (porta TCP do meta-servidor e faixa UDP das partidas). Exige TLS para o HTTP.
3. **VPS barata** (1–2 vCPU, 1–2 GB de RAM).

A decisão fica para a Etapa 12. O código não depende dela. Desde a Etapa 7, um único processo do servidor dedicado (`--salas=N`) hospeda várias partidas; para o grupo de amigos, 1 sala com bots basta.
