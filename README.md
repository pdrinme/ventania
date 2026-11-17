# Projeto Ventania 

Battle Royale 3D original em terceira pessoa, com construção, bots, lobby social,
progressão persistente, passe de batalha gratuito e loja rotativa de cosméticos.
O alvo são PCs antigos e celulares Android modestos. É um projeto pessoal, feito
para um pequeno grupo de amigos.

> **Inspiração e identidade.** O jogo se inspira no *gênero* e na *sensação* dos
> Battle Royales cartunescos com construção (fim dos anos 2010). Ele **não** usa
> nomes, personagens, mapas, itens, interface, áudio ou arquivos de nenhum jogo
> existente. Nome, moeda e conteúdo são originais. Veja
> [ASSET_LICENSES.md](ASSET_LICENSES.md).

## Status

**Etapa 4 (mapa e Battle Royale): implementada e testada com clientes simulados.** Partida Battle Royale na Ilha Ventania (~600 m, 6 pontos de interesse), com loot pelo inventário completo, picareta permanente, Tormenta em 7 fases, eliminações, espectador, vitória e partidas seguidas no servidor dedicado. O campo de treino (bonecos, reaparecer) continua disponível. **Etapa 5 (construção): implementada e testada com clientes simulados.** Parede, piso, rampa e teto numa grade de 4 m, edição (portas e janelas), vida, rachaduras, destruição, desabamento sem apoio, coleta de materiais com a picareta, e as casas do mapa destrutíveis no mesmo sistema. **Etapa 6 (bots): implementada e testada.** As partidas são completadas com bots em três dificuldades, que saltam do ônibus, saqueiam, combatem, curam, fogem da Tormenta e (no Difícil) constroem.
Veja [ROADMAP.md](ROADMAP.md).

## Documentos

| Documento | Conteúdo |
|---|---|
| [ARCHITECTURE.md](ARCHITECTURE.md) | Tecnologia, processos, rede, persistência, segurança, desempenho |
| [GAME_DESIGN.md](GAME_DESIGN.md) | Regras do jogo, modos, armas, construção, bots, economia, passe, loja |
| [ROADMAP.md](ROADMAP.md) | Etapas, dependências, critérios de aceite e progresso real |
| [ASSET_LICENSES.md](ASSET_LICENSES.md) | Política de assets e registro de licenças |
| [docs/assets/PIPELINE.md](docs/assets/PIPELINE.md) | Pipeline Blender → GLB → Godot, formatos, convenções, catálogo |
| [docs/assets/IMPORTACAO_GODOT_E_OTIMIZACAO.md](docs/assets/IMPORTACAO_GODOT_E_OTIMIZACAO.md) | Importação na Godot e otimização de geometria, texturas e materiais |
| [docs/assets/REFERENCIAS.md](docs/assets/REFERENCIAS.md) | Uso de referências visuais e o fluxo referência → asset original |
| [docs/TESTE_EM_HARDWARE.md](docs/TESTE_EM_HARDWARE.md) | Como instalar, rodar o teste de desempenho e reportar |
| [docs/art/GUIA_DE_ESTILO.md](docs/art/GUIA_DE_ESTILO.md) | Direção visual, paleta, shader cartoon, proporções e kit inicial |

## Tecnologia (resumo)

- **Engine:** Godot **4.7.2-stable**, GDScript, renderizador **Compatibility** (OpenGL ES 3).
- **Servidor de partida:** o mesmo projeto Godot exportado como servidor dedicado headless, com rede ENet e autoridade do servidor.
- **Meta-servidor** (contas, amigos, grupos, matchmaking, inventário, moeda, passe, loja): Python 3.11+ **só com a biblioteca padrão** (asyncio + sqlite3), com HTTP/JSON.
- **Plataformas:** Windows, Linux e Android (cliente). Linux e Windows (servidores).

## Estrutura planejada do repositório

```
/
├── game/        Projeto Godot (cliente + servidor de partida, código compartilhado)
├── backend/     Meta-servidor Python (stdlib) + configs de temporada/loja/catálogo
├── tools/       Scripts de exportação, validação de licenças, ferramentas de conteúdo
└── docs/        Documentação complementar (protocolos, guias de instalação)
```

## Como rodar

Builds prontas: veja [docs/TESTE_EM_HARDWARE.md](docs/TESTE_EM_HARDWARE.md).

A partir do código-fonte, com o Godot 4.7.2:

```bash
godot --path game
```

Meta-servidor (opcional, Python 3.11+, sem dependências):

```bash
cd backend && python3 -m meta_server
```

Servidor de partida dedicado (o mesmo executável do jogo):

```bash
godot --headless --path game -- --servidor --porta=24800
```

Por padrão o servidor roda partidas Battle Royale seguidas (começa com 2+ jogadores, ou depois de 90 s com 1). Opções: `--modo=treino` (campo de treino), `--min-jogadores=N`, `--config=arquivo.json` (sobrescreve `game/data/partida.json`).

Todos os testes (Python, Godot, fumaça, integração, servidor dedicado e desempenho):

```bash
GODOT=/caminho/do/godot tools/run_tests.sh
```

Exportar as builds:

```bash
godot --headless --path game --export-release "Linux" ../builds/linux/ventania.x86_64
```

```bash
godot --headless --path game --export-release "Windows" ../builds/windows/Ventania.exe
```
