# Projeto Ventania (codinome provisório)

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

**Etapa 0, pipeline de assets (0.5) e kit visual (0.6): concluídos.** Ainda não há código de gameplay.
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

Ainda não há nada executável. As instruções chegam na Etapa 1. O guia de
instalação para os amigos chega na Etapa 12.
