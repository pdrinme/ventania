# Teste em hardware real

Objetivo: medir como o Ventania roda no **seu PC fraco** e no **seu celular**,
para calibrar perfis gráficos e orçamentos antes do gameplay (Etapa 2).

## 1. Instalar

| Plataforma | Arquivo | Como abrir |
|---|---|---|
| Windows 10/11 (64 bits) | `Ventania-0.7.0-windows.zip` | Extraia e abra `Ventania.exe`. O Windows pode avisar "aplicativo não reconhecido": clique em **Mais informações → Executar assim mesmo** (o executável não tem assinatura digital). |
| Linux (64 bits) | `Ventania-0.7.0-linux.zip` | Extraia, rode `chmod +x ventania.x86_64` e depois `./ventania.x86_64`. |
| Android | `ventania-0.7.0.apk` | Permita "instalar apps de fontes desconhecidas" e abra o arquivo. É uma versão de depuração, para teste. |
| Servidor dedicado (Linux) | `VentaniaServidor-0.7.0-linux.zip` | Extraia e rode `./ventania_servidor.x86_64 --headless -- --servidor` (ver a seção 2.1). |
| Servidor dedicado (Windows) | `VentaniaServidor-0.7.0-windows.zip` | Extraia e rode `VentaniaServidor.console.exe --headless -- --servidor` num terminal. |

Requisito gráfico: OpenGL 3.3 (PC) ou OpenGL ES 3.0 (celular). Quase qualquer
GPU integrada a partir de 2012 atende.

## 2. Jogar (Etapas 2 e 3)

**Treino sozinho:** Menu → **Jogar: campo de treino**.

| Ação | PC | Controle | Celular |
|---|---|---|---|
| Mover | WASD | Analógico esquerdo | Joystick (metade esquerda da tela) |
| Olhar | Mouse | Analógico direito | Arrastar na metade direita |
| Correr | Shift | L3 (segurar) | Empurrar o joystick até a borda |
| Pular | Espaço | A | Botão Pular |
| Agachar | Ctrl (segurar) | R3 (alterna) | Botão Agachar (alterna) |
| Mirar (zoom) | Botão direito | LT | — |
| Atirar / usar item | Botão esquerdo | RT | Botão Atirar (arraste nele para mirar) |
| Recarregar | R | X | Botão Recarga |
| Pegar item / abrir baú (segurar) | E | Y | Botão Pegar |
| Trocar de espaço | 1–5 ou roda do mouse | LB / RB | Tocar no espaço |
| Picareta | F | ► (direcional direito) | Tocar no 1º espaço |
| Inventário | Tab | Select / Back | Botão Mochila |
| Mapa | M | ▲ (direcional cima) | — |
| Modo construção | Q | B | Botão Construir |
| Peça (no modo construção) | 1–4 ou roda | LB / RB | Botão Peça |
| Material (no modo construção) | R | X | Botão Material |
| Colocar peça (segurar = sequência) | Botão esquerdo | RT | Atirar |
| Editar peça sua | G | ▼ (direcional baixo) | Botão Editar (Atirar troca o ladrilho) |
| Pausa | Esc | Start | Botão II / voltar |

Para testar: atire nos três **bonecos de treino** à frente do ponto inicial,
abra os baús (há um no topo da torre de pedra e outro no telhado da caixa de
metal), troque de arma, use curativos e células de escudo. Com um amigo no mesmo
servidor, dá para trocar tiros de verdade. Quem é eliminado reaparece em 4 s.

**Battle Royale (Etapa 4):** no menu, **Battle Royale: Ilha Ventania** abre uma
partida sozinho (serve para conhecer a ilha e a Tormenta: você vence se ainda
estiver vivo quando a última fase terminar). Com amigos, o servidor dedicado roda
partidas seguidas: todos esperam no Mirante, a contagem começa com 2 ou mais
jogadores, cada um aparece num ponto da ilha só com a picareta, e quem é eliminado
assiste aos outros (Atirar troca de jogador, Esc volta ao menu).

**Jogar com amigos (mesma rede ou VPN):**
1. Em um PC, abra um terminal na pasta do jogo e rode o servidor:

```bash
./ventania.x86_64 --headless -- --servidor
```

   No Windows: `Ventania.console.exe --headless -- --servidor` (se existir) ou `Ventania.exe --headless -- --servidor`.
   Isso roda partidas Battle Royale. Para o campo de treino, acrescente `--modo=treino`.
2. Libere a porta **24800 UDP** no firewall desse PC.
3. Cada jogador vai em **Configurações → Rede**, preenche **Seu nome** e **Servidor de partida** (`IP-DO-PC:24800`) e toca em **Entrar em servidor**. Quem roda o servidor também pode jogar no mesmo PC usando `127.0.0.1:24800`.

### 2.1 Servidor dedicado e salas (Etapa 7)

O servidor dedicado é um executável separado, sem gráficos (bem mais leve que o
jogo). Opções úteis:

| Opção | O que faz |
|---|---|
| `--porta=24800` | primeira porta UDP |
| `--salas=2` | duas partidas independentes no mesmo processo (portas 24800 e 24801) |
| `--max-jogadores=16` | humanos por sala; acima disso o jogo mostra "Sala cheia" e indica a outra sala |
| `--bots=16` | completa a partida com bots até esse total (`--bots=0` desliga) |
| `--min-jogadores=2` | humanos para começar a contagem |
| `--relatorio=30` | a cada 30 s, escreve no terminal a banda por cliente, o tempo de tick, reconexões e expulsões |

Exemplo, duas salas com bots: `./ventania_servidor.x86_64 --headless -- --servidor --salas=2 --bots=16`.
Libere no firewall as portas UDP de todas as salas (24800–24801 no exemplo).

**Se a conexão cair** no meio da partida (Wi-Fi, troca para 4G, celular bloqueado),
o personagem fica parado no mesmo lugar por até 60 s. O jogo mostra
"Conexão perdida — reconectando…" e volta sozinho com o mesmo personagem,
inventário e posição. Depois de 60 s sem voltar, o jogador sai da partida e
deixa os itens no chão.

**Rede ruim de propósito (teste):** o jogo aceita `--lag=120 --jitter=30 --perda=2`
(atraso em ms, variação em ms e % de pacotes perdidos), por exemplo
`./ventania.x86_64 -- --lag=120 --perda=2`. O canto da tela mostra "sim 120 ms/2%".

### 2.2 Aceite da Etapa 7: 2 PCs + 1 Android na mesma partida

1. **PC 1:** rode o servidor dedicado com `--bots=16 --relatorio=30` e anote o IP do PC (`ipconfig` / `ip addr`).
2. **PC 1 (mesmo PC), PC 2 e o celular:** **Configurações → Rede**, um nome diferente em cada um, servidor `IP-DO-PC-1:24800`, **Entrar em servidor**.
3. Com os 3 conectados, a contagem começa e os bots completam até 16. Joguem a partida.
4. **Reconexão:** no meio da partida, desligue o Wi-Fi do celular por uns 10 s e ligue de novo. O jogo deve dizer "Reconectado!" e o personagem continua onde estava, com os mesmos itens. Repita num PC tirando o cabo ou desligando o Wi-Fi.
5. **Banda:** o canto superior da tela mostra `↓ X ↑ Y kbit/s` de cada aparelho. O terminal do servidor mostra a média e o máximo por cliente a cada 30 s. Copie essas linhas e cole na conversa.
6. Mande também: o ping de cada aparelho, se alguém "teleportou" ou travou, e o FPS do celular durante a partida.

Referência medida aqui (3 clientes simulados + 13 bots, localhost): **44–56 kbit/s
de descida e ~4 kbit/s de subida por cliente**, só a carga útil. O ENet acrescenta
cerca de 30–40 bytes de cabeçalho por pacote, o que dá cerca de 15–20 kbit/s a mais.
Mesmo somando, fica muito abaixo de qualquer 3G/4G ou Wi-Fi doméstico.

Ligue **Configurações → Gráficos → Mostrar FPS** para ver o FPS durante a partida e me mande o número (parado, correndo e olhando para as construções).

## 3. Rodar o teste de desempenho

1. No menu, abra **Vitrine e teste de desempenho**.
2. Deixe em **Perfil: Desempenho** e **Densidade: 1×1** e toque em **Iniciar teste (20 s)**. Não mexa no aparelho durante o teste.
3. Ao terminar, toque em **Copiar resultado** e cole aqui na conversa.
4. Repita com:
   - **Perfil: Equilibrado**, Densidade 1×1;
   - **Perfil: Qualidade**, Densidade 1×1;
   - o perfil que rodou melhor, com **Densidade 2×2** e depois **3×3**. Isso simula uma área com muito mais construções.

5. **Benchmark da Ilha (Etapa 4):** na mesma tela, toque em **Benchmark da Ilha (3 perfis, ~70 s)**. A câmera percorre os pontos de interesse com 16 personagens e a Tormenta, e mede os três perfis em sequência. No fim, o resumo já fica copiado: cole aqui. Também roda pela linha de comando: `./ventania.x86_64 -- --benchmark-ilha`.

Os resultados também ficam salvos (JSON + CSV, frame a frame) em:
- Windows: `%APPDATA%\Godot\app_userdata\Ventania\benchmarks\`
- Linux: `~/.local/share/godot/app_userdata/Ventania/benchmarks/`

## 4. O que observar

- O teste roda **sem limite de FPS e sem vsync** (as suas configurações são restauradas no fim), para medir a folga real. Se no Linux o resultado parar exatamente em 60, o driver está forçando o vsync: rode `vblank_mode=0 ./ventania.x86_64`.
- **FPS médio** e **1% pior**. O "1% pior" mostra os engasgos. A meta é de 30 FPS ou mais no celular e 60 FPS no PC, com "1% pior" acima de 20.
- Se esquentar muito ou travar, anote depois de quanto tempo.
- Se algo aparecer errado (cores, peças faltando, texto cortado), tire uma captura de tela.

## 5. Testar a conexão com o meta-servidor (opcional)

No PC que vai ser o "servidor", com Python 3.11+:

```bash
cd backend
```

```bash
python3 -m meta_server
```

No jogo, vá em **Configurações → Servidor**, digite `http://IP-DO-PC:8080`
(ex.: `http://192.168.0.10:8080`) e toque em **Testar conexão**. O IP do PC
aparece em `ipconfig` (Windows) ou `ip addr` (Linux). Pode ser preciso liberar
a porta 8080 no firewall.

## 6. Android

O preset de exportação já está pronto (`game/export_presets.cfg`, arquiteturas
arm64-v8a e armeabi-v7a, para cobrir celulares de 32 bits). Para gerar o APK falta o
**Android SDK**, que exige aceitar a licença do Google. Há duas opções:

- **No seu PC:** instale o Godot 4.7.2 e o Android SDK (command-line tools, com `build-tools` e `platform-tools`), configure em *Editor → Editor Settings → Export → Android* e exporte o preset "Android".
- **Nesta sessão do Claude:** autorize explicitamente a instalação do SDK com aceite da licença do Google, e o APK é gerado aqui.
