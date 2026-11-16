#!/usr/bin/env bash
# Roda todos os testes do projeto.
# Uso: GODOT=/caminho/para/godot tools/run_tests.sh
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
FALHAS=0
passo() { echo; echo "== $1"; }
checar() { if [ "$1" -ne 0 ]; then echo "!! FALHOU: $2"; FALHAS=$((FALHAS+1)); fi; }

passo "Ferramentas de assets (Python)"
python3 -m unittest discover -s tools/assets/tests 2>&1 | tail -2; checar "${PIPESTATUS[0]}" "assets"
python3 tools/assets/catalog.py validar; checar $? "catálogo"

passo "Meta-servidor (Python)"
(cd backend && python3 -m unittest discover -s tests 2>&1 | tail -2; exit "${PIPESTATUS[0]}"); checar $? "backend"

passo "Godot: importação"
"$GODOT" --headless --path game --import >/dev/null 2>&1
"$GODOT" --headless --path game -s res://tests/test_asset_import.gd 2>&1 | grep -E "ASSETS_IMPORTADOS|FALHA"; checar "${PIPESTATUS[0]}" "importação"

# Erros de script interrompem um teste sem marcar falha: qualquer "SCRIPT ERROR" reprova o grupo.
rodar_godot() {
	local saida
	saida=$("$@" 2>&1); local cod=$?
	echo "$saida" | grep -E "$FILTRO"
	if echo "$saida" | grep -q "SCRIPT ERROR"; then
		echo "$saida" | grep -A2 "SCRIPT ERROR" | head -12
		return 1
	fi
	return $cod
}

passo "Godot: testes unitários"
FILTRO="TESTES|FALHOU|NÃO COMPILOU"
rodar_godot "$GODOT" --headless --path game -s res://tests/run_tests.gd; checar $? "unitários"

passo "Godot: teste de fumaça (jogo completo)"
FILTRO="FUMACA|FALHOU"
rodar_godot timeout 150 "$GODOT" --headless --path game -- --teste-fumaca; checar $? "fumaça"

passo "Encerramento limpo depois de jogar (exit code)"
# Fechar o jogo depois de uma partida não pode travar (bug real da 0.3.1: nó visual órfão)
for i in 1 2 3; do timeout 90 "$GODOT" --headless --path game -- --sair-apos=game,menu >/dev/null 2>&1; c=$?; [ $c -ne 0 ] && break; done
echo "exit=$c"; checar $c "encerramento"

passo "Integração cliente <-> meta-servidor"
PORTA=$(python3 -c "import socket; s=socket.socket(); s.bind(('127.0.0.1',0)); print(s.getsockname()[1]); s.close()")
TMPDB=$(mktemp -d)
(cd backend && VENTANIA_DB="$TMPDB/meta.sqlite3" exec python3 -m meta_server --host 127.0.0.1 --port "$PORTA") >"$TMPDB/server.log" 2>&1 &
PID=$!
for i in $(seq 1 50); do grep -q "ouvindo" "$TMPDB/server.log" 2>/dev/null && break; sleep 0.1; done
timeout 60 "$GODOT" --headless --path game -s res://tests/integration/test_meta_health.gd -- "http://127.0.0.1:$PORTA" 2>&1 | grep -E "INTEGRACAO|FALHA"; checar "${PIPESTATUS[0]}" "integração"
kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null; rm -rf "$TMPDB"

passo "Servidor dedicado de partida (outro processo) + 2 clientes"
PORTA=$(python3 -c "import socket; s=socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.bind(('127.0.0.1',0)); print(s.getsockname()[1]); s.close()")
LOGSRV=$(mktemp)
"$GODOT" --headless --path game -- --servidor --modo=treino --porta="$PORTA" >"$LOGSRV" 2>&1 &
PID=$!
for i in $(seq 1 100); do grep -q "servidor dedicado pronto" "$LOGSRV" 2>/dev/null && break; sleep 0.1; done
timeout 60 "$GODOT" --headless --path game -s res://tests/integration/test_dedicated_server.gd -- 127.0.0.1 "$PORTA" 2>&1 | grep -E "DEDICADO|FALHA"; checar "${PIPESTATUS[0]}" "servidor dedicado"
kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null; rm -f "$LOGSRV"

passo "Etapa 4: partida Battle Royale completa (clientes simulados, servidor no processo)"
FILTRO="PARTIDA_BR|FALHOU|partida:"
rodar_godot timeout 600 "$GODOT" --headless --path game -s res://tests/integration/test_partida_br.gd -- 6; checar $? "partida BR"

passo "Etapa 4: partida BR no servidor dedicado (outro processo) com 4 clientes simulados"
PORTA=$(python3 -c "import socket; s=socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.bind(('127.0.0.1',0)); print(s.getsockname()[1]); s.close()")
LOGSRV=$(mktemp)
"$GODOT" --headless --path game -- --servidor --modo=br --porta="$PORTA" --config=res://tests/integration/partida_rapida.json --min-jogadores=4 >"$LOGSRV" 2>&1 &
PID=$!
for i in $(seq 1 150); do grep -q "servidor dedicado pronto" "$LOGSRV" 2>/dev/null && break; sleep 0.1; done
rodar_godot timeout 400 "$GODOT" --headless --path game -s res://tests/integration/test_partida_br.gd -- 4 --externo="$PORTA"; checar $? "partida BR dedicada"
grep -E "partida [0-9]+ (começou|terminou)" "$LOGSRV" | sed 's/^.*\] /   servidor: /'
kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null; rm -f "$LOGSRV"

passo "Desempenho do servidor (24 jogadores): campo de treino e ilha"
"$GODOT" --headless --path game -s res://tests/perf/perf_server.gd -- 24 300 2>&1 | grep PERF_SERVIDOR
echo "   (Ilha Ventania, jogadores espalhados pelos POIs):"
"$GODOT" --headless --path game -s res://tests/perf/perf_server.gd -- 24 300 ilha 2>&1 | grep PERF_SERVIDOR

echo
if [ "$FALHAS" -eq 0 ]; then echo "TODOS OS TESTES PASSARAM"; else echo "$FALHAS GRUPO(S) FALHARAM"; fi
exit "$FALHAS"
