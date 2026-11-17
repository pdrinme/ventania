# Ventania — Guia de instalação (para quem vai jogar)

## 1. Baixar e instalar

| Aparelho | Arquivo | Como instalar |
|---|---|---|
| Windows 10/11 (64 bits) | `Ventania-<versão>-windows.zip` | Extraia a pasta e abra `Ventania.exe`. Se o Windows avisar "aplicativo não reconhecido", clique em **Mais informações → Executar assim mesmo** (o jogo não tem assinatura digital paga). |
| Linux (64 bits) | `Ventania-<versão>-linux.zip` | Extraia, rode `chmod +x ventania.x86_64` e depois `./ventania.x86_64`. |
| Android 7+ | `ventania-<versão>.apk` | Abra o arquivo no celular. Se pedir, permita **instalar apps desta fonte**. |

Requisitos: placa de vídeo com OpenGL 3.3 (PC) ou OpenGL ES 3.0 (celular). Quase qualquer computador ou celular dos últimos 10 anos atende.

Para conferir se o arquivo veio inteiro, compare com o `SHA256SUMS.txt` que vem junto.

## 2. Primeira vez

1. Abra o jogo. O lobby aparece com o seu personagem.
2. **Configurações → Servidor**: coloque o endereço que quem hospeda passou, por exemplo `http://192.168.0.10:8080` (ou o IP da VPN). Volte.
3. Toque em **Entrar → Não tenho conta: criar uma**. Você só precisa de um nome e uma senha (sem e-mail e sem dados pessoais).
4. Ajuste em **Configurações**:
   - **Gráficos:** o perfil "Desempenho" é o mais leve; "Qualidade" é para PCs mais fortes.
   - **Controles:** troque as teclas ou o tamanho dos botões de toque.
   - **Áudio:** volumes.

## 3. Jogar

- **JOGAR:** o cartão acima do botão mostra o modo. Toque nele para trocar.
  - **Battle Royale:** online com amigos. Os bots completam a partida se não houver gente suficiente.
  - **Sala privada:** você cria um código e os amigos entram com ele. A partida começa quando você mandar.
  - **Campo de treino online:** treino com o grupo.
  - **Battle Royale solo / Campo de treino:** offline, não precisam de servidor.
  - **Servidor por endereço:** entra direto num servidor sem conta (endereço em Configurações → Rede).
- **Amigos** (ícone de pessoas): adicione pelo nome da conta, aceite os pedidos e convide para o grupo (até 4). Só o líder começa a partida.
- **Passe:** sobe com o XP das partidas e das missões. É todo gratuito.
- **Missões:** 3 diárias e 5 semanais.
- **Loja:** trajes à venda por Faíscas, a moeda do jogo. Faíscas vêm do passe, dos níveis e das missões. **Não existe compra com dinheiro real.**
- **Perfil** (chip com o nível): coleção (para equipar), desbloqueios, extrato de Faíscas e partidas.

### Controles

| Ação | PC | Controle | Celular |
|---|---|---|---|
| Mover / olhar | WASD / mouse | analógicos | joystick à esquerda / arrastar à direita |
| Pular / agachar / correr | Espaço / Ctrl / Shift | A / R3 / L3 | botões / empurrar o joystick até a borda |
| Atirar / mirar | botão esquerdo / direito | RT / LT | botão Atirar |
| Recarregar / pegar | R / E | X / Y | botões Recarga / Pegar |
| Picareta / itens | F / 1–5 | ► / LB-RB | tocar na barra |
| Construir / editar | Q / G | B / ▼ | botões Construir / Editar |
| Mochila / mapa / pausa | Tab / M / Esc | Select / ▲ / Start | botões Mochila / II |

## 4. Problemas comuns

| O que aparece | O que fazer |
|---|---|
| "Servidor offline" no lobby | Confira o endereço em Configurações → Servidor e se quem hospeda ligou o servidor. Os modos offline continuam funcionando. |
| "O servidor não respondeu" ao entrar na partida | Quem hospeda precisa liberar a porta **UDP** das salas no firewall (veja o guia de hospedagem). |
| "Conexão perdida — reconectando…" | Normal se a rede oscilar: o jogo volta sozinho em até 1 minuto, com o mesmo personagem. |
| "Versão do jogo diferente da do servidor" | Baixe a mesma versão que quem hospeda está usando. |
| "Sala cheia" | Espere a partida acabar ou use outra sala. |
| Jogo travando no celular | Configurações → Gráficos → perfil **Desempenho** e Resolução 3D menor. |

Os registros (logs) do jogo ficam em:
- Windows: `%APPDATA%\Godot\app_userdata\Ventania\logs\`
- Linux: `~/.local/share/godot/app_userdata/Ventania/logs/`

Mande esses arquivos a quem hospeda se algo der errado.
