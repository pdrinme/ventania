# Game Design — Projeto Ventania

Versão 0.1 (Etapa 0). Todos os números são **valores iniciais de balanceamento**.
Eles ficam em arquivos de dados e serão ajustados com testes de jogo.

## 1. Identidade

- **Pilares:** (1) diversão antes de gráficos, (2) jogar com amigos com poucos humanos, (3) construção rápida e legível, (4) progressão gratuita e justa, (5) roda em hardware modesto.
- **Tom:** cartunesco, colorido e bem-humorado. Silhuetas fortes, paleta saturada e formas exageradas.
- **Originalidade:** nomes, personagens, mapa, itens, sons e UI são criados para este projeto. As inspirações são de *gênero* (Battle Royale com construção e loja de cosméticos). Não haverá nomes ou designs reconhecíveis de outros jogos. Os nomes abaixo são provisórios e configuráveis.
  - Nome do jogo: **Ventania** (codinome).
  - Moeda virtual: **Faíscas** (nome e ícone configuráveis em `backend/config/currency.json`).
  - Zona da tempestade: **a Tormenta**.

## 2. Loop principal

1. Entrar no **lobby**, ver o personagem, montar o grupo e escolher o modo.
2. Entrar na **partida**: ônibus ou planador de entrada (provisório: aeronave original que cruza o mapa) e salto.
3. **Coletar**: armas, munição, curas, escudos e materiais (com a ferramenta de coleta).
4. **Sobreviver**: lutar, construir para se proteger e fugir da Tormenta.
5. **Fim**: vitória ou eliminação (com espectador), seguidos da tela de resultados, do XP, do progresso de missões e do retorno ao lobby.
6. **Progresso**: subir o passe, ganhar Faíscas, comprar ou equipar cosméticos.

## 3. Modos

| Modo | Times | Observações |
|---|---|---|
| Solo | 1 | |
| Dupla | 2 | Vagas do grupo preenchidas por bots, se o jogador quiser |
| Esquadrão | 4 | Idem |
| Privada | Configurável | Criada pelo líder: modo, nº de bots, dificuldade e tamanho do mapa |
| Treino | 1 | Local, contra bots, sem servidor externo (útil para testar e jogar offline) |

- **Tamanho da partida:** até 24 participantes na primeira versão. Mínimo de 1 humano. Os bots completam o resto.
- **Opções do líder ou da sala:** quantidade de bots (0 até o máximo), dificuldade (Fácil, Normal, Difícil ou Mista) e "iniciar agora" com as vagas preenchidas por bots.
- **Matchmaking:** com poucos jogadores, a fila espera um tempo configurável (ex.: 20 s) por outros grupos e depois completa com bots.

## 4. Personagem e controles

- Câmera em terceira pessoa por cima do ombro, com troca de ombro e mira com zoom.
- Ações: andar, correr (sprint), pular, agachar, interagir (segurar), recarregar, trocar de slot, modo construção e modo edição.
- **Velocidades** (m/s): andar 4,5, correr 6,5, agachado 2,5, salto de cerca de 1,4 m.
- **Vida 100 e escudo 100.** O dano passa primeiro pelo escudo.
- Dano de queda acima de uma altura limite.
- **PC:** teclado e mouse com teclas remapeáveis, além de controle (gamepad).
- **Android:** joystick virtual à esquerda, área de câmera à direita, botões contextuais (atirar, pular, agachar, construir) que se reposicionam e redimensionam, e sensibilidade separada para câmera e mira. O HUD tem layout próprio, não é o do PC reduzido.

## 5. Combate

- **Raridades** (cor e multiplicador de status): Comum (cinza), Incomum (verde), Raro (azul), Épico (roxo), Lendário (dourado) e **Mítico** (degradê animado rosa→ciano; só por eventos e recompensas, nunca em sorteio).
- **Nomes exibidos:** sempre tipo + nome próprio (ex.: Rifle de Assalto Rajada, Espingarda Trovão, Submetralhadora Zumbido, Pistola Faísca, Rifle de Precisão Gavião).
- **Armas implementadas (Etapa 3)**, com valores em `game/data/itens.json`: **Rajada** (fuzil), **Trovão** (escopeta), **Zumbido** (submetralhadora), **Faísca** (pistola) e **Gavião** (precisão). Os explosivos ficam para depois.
- **Arquétipos de arma:**

| Arquétipo | Papel | Notas |
|---|---|---|
| Fuzil de assalto | Médio alcance | Espalhamento cresce em rajada |
| Escopeta | Curto alcance | Pellets, dano alto e cadência baixa |
| Submetralhadora | Curto e médio | Cadência alta e dano baixo |
| Pistola | Reserva | Precisa |
| Fuzil de precisão | Longo alcance | Zoom e tiro único |
| Explosivo | Antiestrutura | Dano alto contra construções (fase posterior) |

- **Munição** em 4 tipos (leve, média, pesada e cartuchos) com limite por tipo.
- **Recarga** por pente, cancelada ao trocar de arma.
- **Inventário:** picareta permanente no 1º espaço à esquerda, depois 5 espaços (armas e consumíveis), mais munição e materiais separados (reservas com máximo por tipo). Tela de inventário (Tab / botão Select / botão Mochila no toque) para ver detalhes, mover entre espaços (arrastar ou "Mover"), dividir pilhas, largar quantidades e pegar itens próximos escolhendo o espaço a substituir.
- **Picareta:** ferramenta permanente (não cai, não é largada nem trocada). Golpe de ~0,6 s com impacto único no meio do movimento, até 2,4 m. Causa 20 de dano em jogadores. Na Etapa 5, danifica construções e coleta materiais (madeira, pedra e metal). Controles: F no teclado, ► (direcional direito) no controle, toque no 1º espaço da barra; a roda do mouse e LB/RB passam por ela no ciclo.
- **Cura e escudo:** Curativo (+15 de vida até 75, 2,5 s), Kit de cura (+100, 7 s), Célula de escudo pequena (+25 até 50, 2 s) e Célula de escudo grande (+50 até 100, 4 s). O símbolo de cura é um coração coral, e não uma cruz.
- **Baús** com abertura segurando o botão e loot pela tabela da raridade. Também há loot no chão e caixas de munição.
- **Eliminação:** em Solo, a eliminação é direta. Em Dupla e Esquadrão há um estado "caído" com revive, que entra **depois** do básico (Etapa 4+).

## 6. Construção

- **Grade** de células de 4 m × 4 m × 4 m (configurável).
- **Peças:** parede, piso, rampa e teto (pirâmide).
- **Materiais:** madeira (150 de vida, pronta em 1 s), pedra (300, 1,6 s) e metal (500, 2,4 s). Cada peça custa 10 do material e "nasce" com 15% da vida, que cresce até o máximo. Máximo de 999 de cada no inventário. Valores em `data/construcao.json`.
- **Limite:** 1200 peças de jogadores por partida (medido).
- **Edição:** cada peça tem uma máscara de ladrilhos (ex.: parede 3×3, piso 2×2) para criar portas, janelas e cantos. A edição é confirmada pelo servidor.
- **Destruição:** por dano ou por coleta. Peças sem apoio desabam por verificação de conectividade com o chão, feita só no servidor e em lotes.
- **Coleta:** a picareta golpeia props e construções do mapa: árvores e arbustos = 7 de madeira, rochas = 6 de pedra, casas do mapa = 4 do material da peça por golpe e +10 ao derrubar (o metal vem das casas do Porto Ferrugem). Construções de jogadores não dão material. A picareta tira 50 de vida das peças; os tiros tiram o dano da arma.
- **Desempenho:** peças renderizadas com MultiMesh por tipo e material, colisões em pool e limite global de peças por partida.

## 7. Partida Battle Royale

- **Mapa inicial pequeno — Ilha Ventania:** ~600 m × 600 m (área jogável de 524 m entre as praias), relevo suave com o morro do Mirante no centro e vegetação instanciada. Pontos de interesse originais: **Vila Brisa** (casas de madeira), **Pedreira Cinza** (torres e casas de pedra, rochas), **Porto Ferrugem** (galpões e contêineres de metal), **Fazenda Girassol** (celeiro de dois andares e plantação), **Mirante do Vento** (torre de pedra com baú no topo) e **Acampamento Coral** (cabanas), mais 12 cabanas espalhadas. São 37 baús e 102 pontos de loot. As construções ainda não são destrutíveis nem coletáveis: isso entra na Etapa 5.
- **Fluxo da partida:** espera no Mirante (sem dano) → contagem de 10 s → cada jogador aparece num ponto diferente da ilha só com a picareta → loot, combate e Tormenta → vitória → resultados (colocação, eliminações, tempo vivo) → nova partida em 15 s. Não há ônibus nem paraquedas por enquanto (ideia para depois).
- **Tormenta:** 7 fases (`data/partida.json`): esperas de 60 → 20 s, fechamentos de 45 → 20 s, raios 190 / 120 / 75 / 45 / 25 / 10 / 0 m e dano de 1, 1, 2, 5, 8, 10 e 15 por segundo, só na vida. Uma partida dura no máximo ~10 min. O centro da próxima zona é sorteado dentro da zona atual e sempre em terra.
- **Vitória:** sobra um jogador ou time. Depois disso aparecem a tela de resultados e a volta ao lobby.
- **Espectador:** ao ser eliminado, o jogador acompanha quem o eliminou ou um companheiro de time, e pode voltar ao lobby a qualquer momento.

## 8. Bots

- **Arquitetura:** híbrida e leve. A decisão é por *utility scoring* com inércia; a execução é feita por estados.
  - **Estados:** explorar, saquear, abrir baú, coletar, ir para a zona, combater, cobertura, recuar, perseguir, investigar (olha em volta ao chegar) e curar.
  - **Ritmo:** as decisões rodam a 2,5–7 Hz conforme a dificuldade, com atraso aleatório entre bots. Longe de humanos, a 1 Hz. O movimento segue o tick.
- **Percepção, sem "saber magicamente":**
  - vê por cone e raycast, com orçamento de raios por tick;
  - lembra a última posição VISTA (tempo de memória por dificuldade);
  - um tiro ouvido vira um ponto para investigar e não revela o atirador;
  - levar dano revela só a direção do disparo.
- **Navegação:** grafo na grade de 4 m da construção, com chão, andares e ligações por escadas e rampas, atualizado na hora quando peças surgem ou somem.
  - As portas são pontos de passagem exatos.
  - **Recuperação de travamento**, com um monitor de progresso que distingue esperar ou observar de estar preso:
    1. com 1,5 s sem progresso: manobra (recua, pula, passo de lado);
    2. com 3 s: evita a aresta onde travou e recalcula a rota;
    3. depois de 3 recuperações no mesmo alvo: desiste dele.
- **Combate:**
  - a mira assenta com o tempo de visada (começa com 3× o erro);
  - rajadas nas armas automáticas;
  - distância preferida por arma (escopeta perto, rifle de precisão longe);
  - passos laterais;
  - cobertura (um ponto que o inimigo não vê), onde recarrega e cura;
  - recuo em desvantagem; troca de arma pela distância.
- **Loot e exploração:**
  - escolhe itens pelo valor para o próprio inventário (arma nova, raridade melhor, cura que falta);
  - explora cômodos de edifícios ainda não visitados, inclusive andares de cima;
  - desiste de itens inalcançáveis e considera a Tormenta.
- **Dificuldades** (`data/bots.json`) mudam a qualidade das decisões, não só a mira:

| | Fácil | Médio | Difícil |
|---|---|---|---|
| Decisões por segundo | 2,5 | 5 | 7 |
| Reação | 0,9 s | 0,55 s | 0,3 s |
| Erro de mira (assentada) | 6° | 3,2° | 1,6° |
| Tempo para assentar a mira | 1,4 s | 0,9 s | 0,55 s |
| Memória da última posição | 3 s | 6 s | 10 s |
| Investiga tiros ouvidos | 30% | 70% | sempre |
| Usa cobertura | nunca | 50% | 90% |
| Recua em desvantagem | não | abaixo de 45 | abaixo de 70 |
| Atira andando | não | não | sim |
| Explora edifícios | 40% | 70% | 85% |

  As partidas são completadas com bots até 16 jogadores (1 Fácil : 2 Médios : 1 Difícil). Os nomes são sorteados de uma lista de 1000 nomes de jogadores (`data/nomes_jogadores.txt`), sem mostrar a dificuldade.
- **Testes:**
  - `test_bots` (partida completa) confere saque, combate, cura, cobertura, perseguir/investigar, Tormenta, andares de cima e menos de 1% do tempo preso;
  - `test_navegacao` manda um bot até cada baú e ponto de loot do mapa.

## 8.1 Edifícios e interiores

- **Escadas reais** em todo edifício de vários andares:
  - em U, num cômodo, com dois lances de 9 degraus (espelho de 20 cm, piso de 27 cm), patamar, parede central e corrimãos;
  - madeira nas casas, concreto nas lojas e prédios, metal nos galpões;
  - guarda-corpo em volta do vão no último andar.
  - As torres externas da Pedreira e do Mirante continuam de rampas (estruturas de construção).
- **Mobília por tipo de edifício:**
  - casa: sala, cozinha, quarto;
  - loja: gôndolas, balcão com caixa, expositor;
  - prédio: escritório embaixo, apartamentos em cima;
  - galpão de metal: máquina, bancada, armários, caixotes, tambores;
  - celeiro: feno, barris, sacos, ferramentas;
  - cabanas.
- **Regras:**
  - só junto às paredes externas;
  - nada na parede da porta;
  - peças altas nunca embaixo de janela ou vitrine;
  - escada e passagens livres;
  - o meio de cada cômodo fica livre.
  - A ordem e a escolha variam por edifício.
- **Loot coerente:** o baú fica encostado numa parede do cômodo do fundo; há pontos de loot em cima de mesas, balcões, bancadas e expositores. A decoração não é interativa.
- **Rampas:** sobem na velocidade normal ao longo do piso (`floor_constant_speed`). O plano e a descida não mudaram.

## 8.2 Mapa e minimapa

- **Identidade de cor por região:**
  - Vila Brisa: menta;
  - Pedreira Cinza: pedra;
  - Porto Ferrugem: ferrugem;
  - Fazenda Girassol: amarelo;
  - Mirante do Vento: céu;
  - Acampamento Coral: coral.
  - Preenchimento leve e contorno; o contorno é calculado das construções de cada região, sem entrar no mar.
- **Mapa completo:** nome de cada região em etiqueta com a cor dela. A imagem tem as estradas e as construções vistas de cima, a zona e a Tormenta.
- **Minimapa:** nomes menores e legíveis, sem cobrir a seta do jogador nem outro nome; a região atual tem prioridade.
- **Região atual:** chip abaixo do minimapa e o nome em destaque ao chegar numa região.
- **Fonte única:** `IlhaVentania.POIS` (id, nome, posição, raio, cor), com `region_bounds()` e `region_at()`.

## 8.3 Fim de partida

- A tela de resultado tem botões **Jogar de novo**, **Voltar ao lobby** e **Assistir** (só com a partida em andamento).
- Mostra:
  - VITÓRIA! com o personagem usado acenando e confete, ou a colocação e o vencedor;
  - as estatísticas que o servidor registra: eliminações, tempo vivo, dano, baús, curas, materiais e construções.
- No PC, o mouse fica livre, o teclado e o controle navegam pelo foco, e Esc é só um atalho. No celular, os botões são grandes.
- O vencedor é decidido pelo servidor e é o mesmo para todos.

## 8.4 Controles de toque

- Botão **Mirar**: segurar mira (FOV, câmera e sensibilidade de mira, mesma lógica do botão direito do PC); arrastar o dedo nele também gira a câmera.
- Só funciona com arma na mão; sem arma, fica apagado.
- Some no modo construção.
- O layout foi conferido sem sobreposição em 16:9, 19,5:9, 20:9 e 4:3.

## 9. Progressão e economia

### 9.1 Nível de conta e XP
- O XP vem de jogar: tempo vivo, colocação, eliminações, baús abertos e missões.
- O mesmo XP alimenta o **passe da temporada**.

### 9.2 Passe de batalha (100% gratuito)
- Nada de trilha premium nem de conteúdo bloqueado por pagamento.
- **Temporada:** cerca de 6–8 semanas, configurada em `backend/config/seasons/<id>.json` (datas, níveis, XP por nível, recompensas e desafios).
- **Tamanho inicial:** 50 níveis. A meta é concluir o passe em **cerca de 25–30 horas de jogo** ao longo da temporada, com as missões semanais acelerando o ritmo.
- **Recompensas:** trajes, ferramentas de coleta, mochilas, emotes, acessórios e Faíscas espalhadas pelos níveis.
- **Ao fim da temporada:** os itens desbloqueados ficam para sempre. Itens do passe podem voltar à loja numa temporada futura (opcional e configurável).

### 9.3 Missões e desafios
- **Diárias** (3), **semanais** (5–7) e **de temporada**, definidas por tipo e parâmetros (ex.: `{"type":"open_chests","count":10}`). O progresso é contado **pelo servidor de partida** e aplicado pelo meta-servidor.

### 9.4 Faíscas (moeda virtual gratuita)
- Fontes: passe, missões, desafios, recompensas de temporada e eventos especiais.
- Uso: só cosméticos da loja.
- Sem compra com dinheiro real nesta versão.
- **Ritmo alvo:** um jogador regular compra 1–2 itens comuns ou raros por semana, ou economiza para um lendário em cerca de 3 semanas. É calibrado com os preços da loja.

### 9.5 Loja rotativa
- **Seções:** "Destaques" (rotação semanal, 2–4 itens) e "Diária" (rotação a cada 24 h, 6 itens).
- **Rotação:** controlada pelo servidor. Existe uma agenda explícita por datas (`backend/config/shop/schedule.json`) e, sem agenda, um sorteio determinístico com semente por data a partir do catálogo elegível, sem repetir itens recentes.
- **Item:** id único, nome, descrição, imagem, raridade, categoria e preço.
- **Imagem:** cada item tem a sua, renderizada do modelo real do jogo com fundo na cor da raridade (cartões da loja, do passe e da coleção).
- **Detalhes:** visualizador 3D com o modelo real (arrastar para girar; Corpo, Rosto e Costas para trajes), categoria, raridade, descrição e preço.
- **Compra:** a tela de confirmação mostra de novo o produto, o preço e o saldo depois. O servidor valida a transação atomicamente; depois aparece "Equipar agora".
- **Preços iniciais por raridade** (Faíscas): Incomum 300, Raro 600, Épico 900, Lendário 1500, Emote 200–500.
- A loja nunca vende vantagem de gameplay.

### 9.6 Categorias de cosméticos
Traje, ferramenta de coleta, mochila, emote, acessório, trilha de queda e
planador. Cada categoria tem um slot de equipamento (emotes têm até 6 slots).

**Trajes são personagens novos**, não recolorações: silhueta, cabeça (ou objeto no
lugar da cabeça), roupa, materiais e paleta próprios, sobre o esqueleto e as
animações compartilhados. Picaretas e planadores são independentes do traje.
Nenhum cosmético muda hitbox, tamanho, dano, coleta ou velocidade.

## 10. Lobby e social

- **Tela principal:** o personagem equipado em destaque com idle, nome, nível, Faíscas, o botão JOGAR (com o seletor de modo), e as abas Loja, Passe, Missões, Armário, Amigos e Configurações.
- **Grupo:** até 4 integrantes, todos visíveis lado a lado no lobby com os cosméticos equipados. O líder escolhe o modo e inicia a partida, e pode passar a liderança. Qualquer um pode sair do grupo.
- **Amigos:** pedido por nome de usuário, aceite ou recusa, lista com status (online, no lobby, em partida) e convite para o grupo.
- **Funciona entre plataformas** porque tudo passa pelo meta-servidor.

## 11. Direção visual (guia para assets originais)

- Low-poly estilizado com *flat shading* ou gradiente simples, texturas pequenas em atlas e paleta saturada.
- Personagens com proporções levemente exageradas (mãos e cabeça maiores) e **um esqueleto padrão para todos**.
- Cenário legível: cada ponto de interesse tem sua cor ou silhueta, e as construções do jogador são bem visíveis.
- UI: tipografia grossa e arredondada (fonte OFL), cards com cor de raridade e animações curtas.
- **Linguagem visual da interface (redesign da Etapa 8, "adesivo ao vento"):**
  - fundo noturno (azul-petróleo → índigo) com rajadas de vento animadas;
  - contorno grosso escuro e sombra dura deslocada, como adesivo ou HQ;
  - botões levemente inclinados (o vento empurrando), com o texto da ação em caixa alta;
  - amarelo só para a ação principal (JOGAR, Atirar no toque) e branco para as secundárias;
  - cartões escuros translúcidos e foco sempre visível (contorno amarelo).

## 12. Fora do escopo inicial

Veículos, pesca, NPCs, modo criativo, chat de voz, eventos ao vivo com mapa
alterado, mapa grande (acima de 1 km) e mais de 50 jogadores. Ficam como
expansões possíveis depois da Etapa 12.
