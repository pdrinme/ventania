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

passo "Godot: testes unitários"
"$GODOT" --headless --path game -s res://tests/run_tests.gd 2>&1 | grep -E "TESTES|FALHOU|NÃO COMPILOU"; checar "${PIPESTATUS[0]}" "unitários"

passo "Godot: teste de fumaça (jogo completo)"
timeout 120 "$GODOT" --headless --path game -- --teste-fumaca 2>&1 | grep -E "FUMACA|FALHOU|SCRIPT ERROR"; checar "${PIPESTATUS[0]}" "fumaça"

passo "Integração cliente <-> meta-servidor"
PORTA=$(python3 -c "import socket; s=socket.socket(); s.bind(('127.0.0.1',0)); print(s.getsockname()[1]); s.close()")
TMPDB=$(mktemp -d)
(cd backend && VENTANIA_DB="$TMPDB/meta.sqlite3" exec python3 -m meta_server --host 127.0.0.1 --port "$PORTA") >"$TMPDB/server.log" 2>&1 &
PID=$!
for i in $(seq 1 50); do grep -q "ouvindo" "$TMPDB/server.log" 2>/dev/null && break; sleep 0.1; done
timeout 60 "$GODOT" --headless --path game -s res://tests/integration/test_meta_health.gd -- "http://127.0.0.1:$PORTA" 2>&1 | grep -E "INTEGRACAO|FALHA"; checar "${PIPESTATUS[0]}" "integração"
kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null; rm -rf "$TMPDB"

echo
if [ "$FALHAS" -eq 0 ]; then echo "TODOS OS TESTES PASSARAM"; else echo "$FALHAS GRUPO(S) FALHARAM"; fi
exit "$FALHAS"
