# Ventania — Guia de hospedagem (para quem vai rodar o servidor)

Um PC (ou um servidor alugado) roda duas coisas, juntas, num pacote só:

| Peça | O que faz | Porta |
|---|---|---|
| **Meta-servidor** (pasta `meta`, Python) | contas, amigos, grupos, matchmaking, progressão, passe, loja | **TCP 8080** |
| **Servidor de partida** (`ventania_servidor` / `VentaniaServidor`) | as partidas, com bots completando as vagas | **UDP 24800** em diante (uma por sala) |

Consumo medido (pacote 1.0.0, 2 salas com 8 jogadores cada):

| Item | Valor |
|---|---|
| Memória do servidor de partida | cerca de 140 MB |
| Memória do meta-servidor | cerca de 30 MB |
| Tempo de processamento por tick (de um orçamento de 33 ms) | 1 a 1,3 ms |
| Envio por jogador | cerca de 20 a 55 kbit/s |

Com 24 jogadores espalhados pela ilha, o tick medido foi de cerca de 3,4 ms. Um PC comum aguenta 2 a 4 salas tranquilamente.

## 1. Ligar (o jeito fácil)

1. Instale o **Python 3.11 ou mais novo**.
   - Windows: baixe em python.org e marque **"Add python.exe to PATH"**.
   - Linux: normalmente já vem; confira com `python3 --version`.
2. Extraia `VentaniaServidor-<versão>-<sistema>.zip`.
3. Ligue:
   - **Linux:** `./iniciar.sh`; para desligar, `./parar.sh`.
   - **Windows:** dois cliques em `iniciar.bat`; para desligar, `parar.bat`.
4. O script mostra o endereço para os amigos: `http://IP-DO-PC:8080`. Cada um põe esse endereço em **Configurações → Servidor** no jogo.

Na primeira vez é criado `dados/segredo.txt`, que liga o meta-servidor ao servidor de partida. **Não compartilhe esse arquivo.** As contas e o progresso de todos ficam em `dados/meta.sqlite3`.

Opções (variáveis de ambiente antes de iniciar):

| Variável | Padrão | O que muda |
|---|---|---|
| `SALAS` | 2 | quantas partidas ao mesmo tempo |
| `BOTS` | 16 | completa cada partida com bots até esse total (0 = sem bots) |
| `PORTA` | 24800 | primeira porta UDP das salas |
| `PORTA_META` | 8080 | porta TCP do meta-servidor |

Exemplo no Linux: `SALAS=3 BOTS=12 ./iniciar.sh`. No Windows: `set SALAS=3` e depois `iniciar.bat`.

**Como funciona o matchmaking:**
- quando alguém toca em JOGAR, o grupo vai para uma sala em espera;
- a sala espera até 30 s por mais pessoas;
- se ninguém mais chegar, os bots completam as vagas e a partida começa;
- se a sala encher de gente antes, começa na hora.

## 2. Como os amigos chegam até você

Escolha **uma** das opções:

| Opção | Bom para | Como |
|---|---|---|
| **Mesma rede (Wi-Fi de casa)** | todos no mesmo lugar | Use o IP local do PC (ex.: `192.168.0.10`). Basta liberar o firewall do PC. |
| **VPN entre amigos** (Tailscale, ZeroTier ou similar) | amigos em casas diferentes, **mais simples e mais seguro** | Todos instalam o mesmo programa de VPN e entram na mesma rede. Use o IP da VPN do PC que hospeda. Não precisa mexer no roteador. |
| **Redirecionar portas no roteador** | sem VPN | No roteador, encaminhe **TCP 8080** e **UDP 24800-24801** para o IP local do PC. Os amigos usam o IP público. Leia a seção 5 (segurança). |
| **Servidor alugado (VPS)** | servidor ligado o tempo todo | Uma VPS Linux pequena (1–2 vCPU, 2 GB). Veja a seção 4. |

### Firewall

- **Windows:** na primeira vez, o Windows pergunta se libera o Python e o VentaniaServidor; marque **Redes privadas** (e públicas, se usar VPN). Ou, em "Firewall do Windows Defender → Regras de entrada", crie regras para TCP 8080 e UDP 24800-24801.
- **Linux (ufw):** `sudo ufw allow 8080/tcp`, depois `sudo ufw allow 24800:24801/udp`.

## 3. Administração

Rode as ferramentas na pasta do pacote:

| Comando | Para quê |
|---|---|
| `python3 ferramentas/admin_loja.py listar` | itens do catálogo, preços e origem (loja, passe, inicial) |
| `python3 ferramentas/admin_loja.py prever --dias 7` | o que a loja vai mostrar nos próximos dias |
| `python3 ferramentas/admin_loja.py agendar --data 2026-11-23 --secao destaques --itens traje_vulcao,traje_relampago` | fixar itens num período (reinicie depois) |
| `python3 ferramentas/admin_loja.py conceder --conta Ana --faiscas 500 --motivo "evento"` | dar Faíscas (fica no extrato com o motivo) |
| `python3 ferramentas/validar_temporada.py` | conferir as temporadas do passe e a estimativa de horas |

No Windows, use `python` no lugar de `python3`.

- **Logs:** `logs/meta.log` e `logs/partida.log`. O servidor de partida registra a cada minuto a banda por jogador, o tempo de processamento e as reconexões.
- **Backup:** copie `dados/` com o servidor desligado (ou a qualquer hora: o banco usa WAL; copie `meta.sqlite3` junto com `meta.sqlite3-wal`, se existir).
- **Atualizar:**
  1. desligue o servidor;
  2. extraia a versão nova numa pasta nova;
  3. copie a pasta `dados/` da antiga para a nova;
  4. ligue.
  - Todos os amigos precisam estar na mesma versão do jogo.
- **Temporadas e loja:** ficam em `meta/config/` (`seasons/`, `shop/`, `catalog/`). Depois de editar, rode `validar_temporada.py` e `admin_loja.py validar`. O meta-servidor não sobe com uma configuração inválida, o que é de propósito.

## 4. VPS Linux (servidor sempre ligado)

```bash
sudo useradd -r -m -d /opt/ventania ventania
```

```bash
sudo -u ventania unzip VentaniaServidor-<versão>-linux.zip -d /opt/ventania
```

Crie `/etc/systemd/system/ventania.service`:

```ini
[Unit]
Description=Ventania (meta-servidor + servidor de partida)
After=network-online.target

[Service]
Type=forking
User=ventania
WorkingDirectory=/opt/ventania/VentaniaServidor-<versão>
Environment=SALAS=2 BOTS=16
ExecStart=/opt/ventania/VentaniaServidor-<versão>/iniciar.sh
ExecStop=/opt/ventania/VentaniaServidor-<versão>/parar.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl enable --now ventania
```

## 5. Segurança

- **As senhas** ficam no banco só como hash (PBKDF2). **Não há e-mail, dados pessoais nem pagamentos reais.**
- **O progresso é decidido pelo servidor:** o jogo do jogador nunca concede XP, Faíscas ou itens a si mesmo. Quem não tem o segredo não consegue enviar resultados de partida, e entrar numa partida exige um ticket assinado pelo meta-servidor.
- **HTTP sem criptografia:** o meta-servidor usa HTTP simples, o que é ok numa rede de casa ou numa VPN. Se você abrir a porta 8080 para a internet (redirecionamento ou VPS), as senhas trafegam sem criptografia. Nesse caso prefira uma VPN, ou coloque um proxy com HTTPS na frente (Caddy ou nginx com Let's Encrypt) e passe aos amigos o endereço `https://`.
- **Segredo:** troque o `dados/segredo.txt` (apague e reinicie) se ele vazar.
