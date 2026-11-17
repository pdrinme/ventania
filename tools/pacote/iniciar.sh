#!/usr/bin/env bash
# Ventania — inicia o servidor completo: meta-servidor (contas, lobby, passe, loja)
# + servidor de partida (salas com bots). Precisa do Python 3.11+ instalado.
# Opções por variável de ambiente: SALAS=2 BOTS=16 PORTA=24800 PORTA_META=8080 EXTRA="..."
cd "$(dirname "$0")"
SALAS=${SALAS:-2}; BOTS=${BOTS:-16}; PORTA=${PORTA:-24800}; PORTA_META=${PORTA_META:-8080}
command -v python3 >/dev/null || { echo "ERRO: instale o Python 3.11 ou mais novo (python3)."; exit 1; }
mkdir -p dados logs
[ -s dados/segredo.txt ] || python3 -c "import secrets; print(secrets.token_urlsafe(24))" > dados/segredo.txt
SEGREDO=$(cat dados/segredo.txt)
if [ -f logs/meta.pid ] && kill -0 "$(cat logs/meta.pid)" 2>/dev/null; then
  echo "Já está rodando. Use ./parar.sh antes de iniciar de novo."; exit 1
fi
(cd meta && VENTANIA_SEGREDO="$SEGREDO" VENTANIA_DB="$PWD/../dados/meta.sqlite3" VENTANIA_PORT="$PORTA_META" exec python3 -m meta_server) > logs/meta.log 2>&1 &
echo $! > logs/meta.pid
for i in $(seq 1 50); do grep -q "ouvindo" logs/meta.log 2>/dev/null && break; sleep 0.2; done
if ! grep -q "ouvindo" logs/meta.log; then echo "ERRO: o meta-servidor não subiu. Veja logs/meta.log"; exit 1; fi
chmod +x ./ventania_servidor.x86_64 2>/dev/null
# shellcheck disable=SC2086
./ventania_servidor.x86_64 --headless -- --servidor --salas="$SALAS" --bots="$BOTS" --porta="$PORTA" \
  --meta="http://127.0.0.1:$PORTA_META" --segredo="$SEGREDO" --relatorio=60 $EXTRA > logs/partida.log 2>&1 &
echo $! > logs/partida.pid
for i in $(seq 1 150); do grep -q "servidor dedicado pronto" logs/partida.log 2>/dev/null && break; sleep 0.2; done
if ! grep -q "servidor dedicado pronto" logs/partida.log; then echo "ERRO: o servidor de partida não subiu. Veja logs/partida.log"; ./parar.sh; exit 1; fi
ULTIMA=$((PORTA + SALAS - 1))
echo "Ventania no ar!"
echo "  Nos aparelhos: Configurações → Servidor → http://IP-DESTE-PC:$PORTA_META"
echo "  Libere no firewall: TCP $PORTA_META e UDP $PORTA-$ULTIMA"
echo "  IPs deste PC: $(hostname -I 2>/dev/null || ipconfig getifaddr en0 2>/dev/null)"
echo "  Logs em ./logs  ·  dados (contas) em ./dados  ·  para desligar: ./parar.sh"
