#!/usr/bin/env bash
# Testa o pacote do servidor como um amigo usaria (Etapa 12): extrai
# VentaniaServidor-<v>-linux.zip numa pasta vazia, liga com ./iniciar.sh e roda
# o teste multiplayer do lobby (contas, amigos, grupo, fila, partida com bots,
# sala privada, XP, passe e loja) contra ele. Depois ./parar.sh.
# Uso: GODOT=/caminho/godot tools/testar_pacote.sh   (depois de tools/empacotar.sh)
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
V=$(grep -oP 'const GAME := "\K[^"]+' game/core/version.gd)
ZIP="builds/release-$V/VentaniaServidor-$V-linux.zip"
[ -f "$ZIP" ] || { echo "falta $ZIP (rode tools/empacotar.sh)"; exit 1; }
TMP=$(mktemp -d)
unzip -q "$ZIP" -d "$TMP"
D="$TMP/VentaniaServidor-$V"
cp game/tests/integration/partida_rapida.json "$TMP/rapida.json"     # tempos curtos de teste
PM=$(python3 -c "import socket; s=socket.socket(); s.bind(('127.0.0.1',0)); print(s.getsockname()[1]); s.close()")
PU=$(python3 -c "import socket; s=socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.bind(('127.0.0.1',0)); print(s.getsockname()[1]); s.close()")
(cd "$D" && PORTA_META=$PM PORTA=$PU SALAS=2 EXTRA="--config=$TMP/rapida.json --bots=8" ./iniciar.sh) || { cat "$D"/logs/*.log | tail -20; exit 1; }
ps -o rss=,comm= -p "$(cat "$D/logs/partida.pid")" "$(cat "$D/logs/meta.pid")" | awk '{printf "   memória: %s %.0f MB\n", $2, $1/1024}'
timeout 480 "$GODOT" --headless --path game -s res://tests/integration/test_lobby.gd -- "http://127.0.0.1:$PM" 2>&1 | grep -E "  ok|FALHOU|LOBBY|SCRIPT ERROR"
COD=${PIPESTATUS[0]}
ps -o rss=,comm= -p "$(cat "$D/logs/partida.pid")" | awk '{printf "   memória do servidor de partida depois do teste (2 salas): %.0f MB\n", $1/1024}'
grep -E "relatório|sala [0-9]:" "$D/logs/partida.log" | sed 's/^.*\] /   servidor: /' | tail -4
(cd "$D" && ./parar.sh) >/dev/null
rm -rf "$TMP"
[ "$COD" -eq 0 ] && echo "PACOTE_OK" || echo "PACOTE_FALHOU"
exit "$COD"
