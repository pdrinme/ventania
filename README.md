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

**Versão 1.0.0: Etapas 0 a 12 concluídas.** A Etapa 13 (os primeiros cosméticos com modelos novos) vem depois.

- **Jogo:**
  - Battle Royale na Ilha Ventania, com Ônibus de Batalha e Tormenta em 7 fases;
  - armas, construção e edição;
  - bots em três dificuldades;
  - campo de treino.
- **Online:**
  - servidor dedicado com várias salas e reconexão;
  - lobby com contas, amigos, grupos de até 4, matchmaking (os bots completam se não houver gente) e sala privada.
- **Progressão:** nível e XP, missões, Faíscas com extrato, passe de batalha gratuito (Temporada 1) e loja rotativa. Nada de dinheiro real.
- **Distribuição:** pacotes para Windows, Linux e Android, e um pacote de servidor completo com scripts de um clique.

Jogar: [docs/GUIA_INSTALACAO.md](docs/GUIA_INSTALACAO.md) · Hospedar: [docs/GUIA_HOSPEDAGEM.md](docs/GUIA_HOSPEDAGEM.md) · Etapas: [ROADMAP.md](ROADMAP.md)

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
| [docs/GUIA_INSTALACAO.md](docs/GUIA_INSTALACAO.md) | Para quem joga: instalar, primeira vez, modos, controles, problemas comuns |
| [docs/GUIA_HOSPEDAGEM.md](docs/GUIA_HOSPEDAGEM.md) | Para quem hospeda: servidor completo, rede, firewall, administração, backup, segurança |
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

Mais opções do servidor:
- Etapa 7: `--salas=N` (várias partidas num processo), `--bots=N`, `--max-jogadores=N`, `--relatorio=S` (banda e tick no log).
- Etapa 8: `--meta=http://IP:8080 --segredo=XXXX` liga as salas ao lobby (matchmaking, salas privadas, tickets). O segredo aparece no log do meta-servidor.

Exemplo completo com lobby:

```bash
godot --headless --path game -- --servidor --salas=2 --bots=16 --meta=http://127.0.0.1:8080 --segredo=XXXX
```

Pacotes de distribuição e teste do pacote do servidor (como um amigo usaria):

```bash
GODOT=/caminho/godot tools/empacotar.sh
```

```bash
GODOT=/caminho/godot tools/testar_pacote.sh
```

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
