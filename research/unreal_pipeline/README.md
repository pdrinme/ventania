# Pesquisa: pipeline de assets da Unreal Engine 4/5

Ambiente local de **estudo técnico** de como jogos em Unreal (como os Battle
Royales de grande escala do fim dos anos 2010) organizam malhas, esqueletos,
animações, materiais, texturas e empacotamento. O objetivo é aprender técnicas,
documentá-las e traduzi-las para o nosso pipeline em Godot.

## Fontes de estudo usadas (legítimas)

| Fonte | O que oferece | Licença / restrição |
|---|---|---|
| **Projeto de exemplo Lyra** (Epic, gratuito) | Shooter em terceira pessoa completo: personagens com esqueleto Mannequin, armas, animações, materiais, empacotamento, configurações mobile | Conteúdo da Epic, **uso só com Unreal Engine** (UE-Only) |
| **Assets do Paragon** (Epic, gratuitos) | Personagens AAA com LODs, materiais complexos e animações | Idem |
| **Templates e Mannequin da UE5** | Esqueleto de referência, retargeting, Animation Blueprint | Idem |
| **Builds que você mesmo empacotar** a partir desses projetos | Formato *cozido* real (`.pak`, `.utoc`/`.ucas`, `.uasset`/`.uexp`/`.ubulk`) para inspecionar no FModel | Seu build do conteúdo acima |
| Documentação oficial da Unreal e palestras públicas da Epic (GDC, Unreal Fest) | Técnicas de otimização e arquitetura | Leitura e citação |

## O que este ambiente não faz, e por quê

| Operação | Limitação | Alternativa |
|---|---|---|
| Abrir builds históricas do Fortnite Capítulo 1 | A Epic não distribui mais essas versões, e as cópias em circulação não são autorizadas | Estudar a mesma engine e o mesmo formato com o Lyra e o Paragon, em builds próprias |
| Extrair arquivos do Fortnite instalado com FModel | O EULA do Fortnite proíbe extrair e fazer engenharia reversa do conteúdo do jogo | Usar o FModel na **sua** build empacotada do Lyra (ver `docs/AMBIENTE.md`) |
| Rodar FModel ou Unreal Editor neste contêiner | O FModel é só para Windows, o editor da UE precisa de GPU e as instalações passam pelo launcher ou pela conta Epic | A instalação é na sua máquina. Este repositório guarda só a documentação e as notas |
| Levar conteúdo estudado para o jogo | Conteúdo UE-Only não pode ir para outra engine, e o jogo só aceita assets originais ou licenciados | Anotar **técnicas e números** (ex.: "LOD1 a cerca de 50% dos tris") e aplicar em assets próprios |

## Estrutura

```
research/unreal_pipeline/
├── README.md                 este arquivo
├── docs/
│   ├── AMBIENTE.md           instalação: UE, Lyra/Paragon, empacotar build própria, FModel, Blender
│   ├── PIPELINE_UNREAL.md    referência técnica: formatos, malhas, esqueletos, materiais, otimização
│   └── UE_PARA_GODOT.md      tradução de cada conceito para o nosso pipeline em Godot
├── notas/                    suas notas de estudo (versionadas, só texto e números)
│   ├── malhas/  esqueletos_animacoes/  materiais_texturas/  otimizacao/  empacotamento/
├── templates/nota_estudo.md  modelo de nota
├── tools/verificar_isolamento.py   garante que nada daqui vaze para game/
└── local/                    NÃO versionado: projetos UE, builds próprias, exportações
```

## Regras

1. Tudo em `local/` fica só na sua máquina (está no `.gitignore`).
2. `notas/` contém texto, números e diagramas próprios. Não contém capturas de assets, malhas ou texturas.
3. Nada de `local/` vai para `game/` ou `assets_src/`. O script `tools/verificar_isolamento.py` checa isso:

```bash
python3 research/unreal_pipeline/tools/verificar_isolamento.py
```
