#!/usr/bin/env bash
# Gera os pacotes de distribuição do Ventania (Etapa 12):
#   builds/release-<versão>/Ventania-<v>-windows.zip   jogo (Windows)
#   builds/release-<versão>/Ventania-<v>-linux.zip     jogo (Linux)
#   builds/release-<versão>/ventania-<v>.apk           jogo (Android, depuração)
#   builds/release-<versão>/VentaniaServidor-<v>-linux.zip    servidor completo (partida + meta + scripts)
#   builds/release-<versão>/VentaniaServidor-<v>-windows.zip  servidor completo (partida + meta + scripts)
# Uso: GODOT=/caminho/godot tools/empacotar.sh
set -eu
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
V=$(grep -oP 'const GAME := "\K[^"]+' game/core/version.gd)
OUT="builds/release-$V"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
rm -rf "$OUT"; mkdir -p "$OUT" builds/linux builds/windows builds/android builds/servidor-linux builds/servidor-windows
echo "== Ventania $V"
python3 tools/validar_temporada.py >/dev/null && python3 tools/admin_loja.py validar >/dev/null
"$GODOT" --headless --path game --import >/dev/null 2>&1 || true
exp() { echo "   exportando $1"; "$GODOT" --headless --path game "$2" "$1" "$3" >"$TMP/export.log" 2>&1 || { tail -20 "$TMP/export.log"; exit 1; }; }
exp "Linux" --export-release ../builds/linux/ventania.x86_64
exp "Windows" --export-release ../builds/windows/Ventania.exe
exp "Servidor Linux" --export-release ../builds/servidor-linux/ventania_servidor.x86_64
exp "Servidor Windows" --export-release ../builds/servidor-windows/VentaniaServidor.exe
exp "Android" --export-debug "../$OUT/ventania-$V.apk"
rm -f "$OUT"/*.idsig
(cd builds/linux && zip -q "../../$OUT/Ventania-$V-linux.zip" ventania.x86_64)
(cd builds/windows && zip -q "../../$OUT/Ventania-$V-windows.zip" Ventania*.exe)
# servidor completo: binário + meta-servidor (só o necessário) + scripts + guia
for so in linux windows; do
  D="$TMP/VentaniaServidor-$V"
  rm -rf "$D"; mkdir -p "$D/meta"
  cp -r backend/meta_server backend/config "$D/meta/"
  find "$D/meta" -name "__pycache__" -prune -exec rm -rf {} +
  cp docs/GUIA_HOSPEDAGEM.md tools/pacote/LEIA-ME.txt "$D/"
  mkdir -p "$D/ferramentas" && cp tools/admin_loja.py tools/validar_temporada.py "$D/ferramentas/"
  if [ "$so" = linux ]; then
    cp builds/servidor-linux/ventania_servidor.x86_64 tools/pacote/iniciar.sh tools/pacote/parar.sh "$D/"
    chmod +x "$D"/*.sh "$D/ventania_servidor.x86_64"
  else
    cp builds/servidor-windows/VentaniaServidor*.exe tools/pacote/iniciar.bat tools/pacote/parar.bat "$D/"
  fi
  (cd "$TMP" && zip -qr "$OLDPWD/$OUT/VentaniaServidor-$V-$so.zip" "VentaniaServidor-$V")
done
cp docs/GUIA_INSTALACAO.md docs/GUIA_HOSPEDAGEM.md "$OUT/"
(cd "$OUT" && sha256sum ./*.zip ./*.apk > SHA256SUMS.txt)
ls -la "$OUT"
echo "PACOTES_OK $OUT"
