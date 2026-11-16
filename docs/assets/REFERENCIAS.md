# Referências visuais: o que usar e como

Referência serve para estudar **estilo**: proporções exageradas, paleta,
legibilidade de silhueta, como o cenário se lê à distância. O resultado é
sempre um asset **modelado do zero** pelo projeto.

## Permitido como referência (em `references/`, local, fora do git)

- Capturas de tela e gravações que você fizer jogando, para análise de estilo, de escala da câmera e de legibilidade.
- Fotos de objetos reais (baús, caixotes, ferramentas, casas, árvores).
- Arte conceitual própria, esboços e moodboards.
- Imagens CC0 e de domínio público.
- Anotações escritas, como "personagens têm cerca de 1,8 m e cabeça de cerca de 1/6 da altura" ou "cores saturadas com sombras azuladas".

## Não entra no projeto

- **Arquivos extraídos de builds de jogos comerciais** (malhas, texturas, esqueletos, animações, sons, mapas), mesmo que circulem publicamente. O projeto não documenta nem automatiza extração de builds do Fortnite (FModel, ferramentas de porting, arquivos históricos de builds). Esses arquivos são propriedade da Epic Games, e usá-los como base de modelagem (retopologia por cima, reaproveitar UVs ou pesos, decalcar silhuetas) gera trabalhos derivados que não podemos distribuir.
- Recriações reconhecíveis de personagens, skins, armas, itens, construções ou locais específicos de outro jogo.

## Fluxo: da referência ao asset original

1. **Análise:** escreva em `notas` do catálogo o que a referência ensina (proporção, paleta, forma). Não copie o objeto em si.
2. **Design próprio:** faça um esboço rápido com um elemento distintivo do projeto (cor, forma ou detalhe que não exista no original).
3. **Blockout** no Blender com primitivas, já dentro do orçamento da categoria.
4. **Modelagem e textura** usando o atlas do projeto.
5. **Revisão:** "alguém olhando reconheceria isso como um item de outro jogo?" Se sim, volte ao passo 2.

## Fontes de assets prontos (licença a conferir por arquivo)

Ver ASSET_LICENSES.md §4 (Kenney, Quaternius, Poly Haven, ambientCG etc.).
Registre cada item com `catalog.py novo --origem terceiros_licenciado --url-origem ... --licenca ...`.
