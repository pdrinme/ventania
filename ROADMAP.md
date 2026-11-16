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
- ⚠️ Pendente do usuário: aprovar a arquitetura e os ajustes acima, e definir onde o código será versionado.

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

### Etapa 1 — Fundação ⬜
Estrutura de diretórios, autoloads, gerenciador de cenas (com tela de carregamento), carregamento de recursos (assíncrono), configurações (perfis Performance, Balanced e Quality com opções independentes), áudio (barramentos e volumes), entrada (InputMap remapeável, detecção de dispositivo), estrutura de dados do jogador (cache de perfil), salvamento local (configurações), cliente HTTP do meta-servidor, esqueleto do meta-servidor e runner de testes.
**Aceite:** o projeto abre e executa no PC, os testes headless passam, o cliente obtém `/v1/health` do meta-servidor, e as configurações persistem entre execuções.

### Etapa 2 — Personagem e gameplay básico ⬜
Personagem em terceira pessoa (esqueleto padrão), câmera, movimentação, corrida, pulo, agachamento, colisões, animações (placeholders originais), controles de PC e controles touch básicos. Movimento via servidor em processo, com predição e reconciliação.
**Aceite:** cena de teste jogável no PC, build Android executando num dispositivo do grupo, e medição de FPS e memória registrada.

### Etapa 3 — Combate e inventário ⬜
Armas (dados em .tres), disparo hitscan validado no servidor, munição, recarga, dano, vida, escudo, inventário de 5 slots, coleta, baús e raridade.
**Aceite:** testes unitários de dano, munição e inventário, e um combate com 2 clientes locais.

### Etapa 4 — Mapa e sistemas Battle Royale ⬜
Mapa pequeno (cerca de 600 m), construções ambientais, loot, Tormenta e zona segura, eliminações, espectador, vitória e encerramento.
**Aceite:** partida completa do início ao fim (com clientes simulados), e benchmark do mapa nos 3 perfis.

### Etapa 5 — Construção ⬜
Parede, piso, rampa e teto, com grade, edição, destruição, desabamento sem apoio e materiais, tudo sincronizado.
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
