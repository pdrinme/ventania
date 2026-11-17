#!/usr/bin/env bash
# Desliga o servidor de partida e o meta-servidor iniciados por ./iniciar.sh
cd "$(dirname "$0")"
for p in partida meta; do
  if [ -f "logs/$p.pid" ]; then kill "$(cat "logs/$p.pid")" 2>/dev/null; rm -f "logs/$p.pid"; fi
done
echo "Ventania desligado."
