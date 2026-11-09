#!/bin/bash
# Normaliza BOM/CRLF dos fontes e compila Win64 e Win32 fora da pasta do projeto.
#   bash tools/build.sh <etiqueta>
# Saída: %TEMP%\NecoBuild\<etiqueta>-win64 e -win32. Compara avisos com base-win64.log / base-win32.log
# (baseline = 0 avisos; se os arquivos base não existirem, só mostra a contagem).
# Win64 cai no fallback do MSB6003 (o compilar.py chama o dcc64 direto), que NÃO roda o post-build:
# por isso o fim deste script copia a WebView2Loader.dll e a lista de bloqueio para a saída Win64.
P="$(cd "$(dirname "$0")/.." && pwd)"
T="$TEMP/NecoBuild"
C=/c/Users/user02/.agent-bridge/skills/delphi-fmx-visual/compilar.py
mkdir -p "$T"
cd "$P" || exit 1
python -I "$P/tools/bomcrlf.py" NecoBrowser.dpr NecoBrowser.dproj src/core/*.pas src/engine/*.pas \
  src/ui/*.pas src/ui/*.fmx tests/CoreTests.dpr | grep -v " ok$"
B64=(); [ -f "$T/base-win64.log" ] && B64=(--base "$T/base-win64.log")
B32=(); [ -f "$T/base-win32.log" ] && B32=(--base "$T/base-win32.log")
python -I -X utf8 $C NecoBrowser.dproj Win64 "$T/$1-win64" "${B64[@]}"; R64=$?
python -I -X utf8 $C NecoBrowser.dproj Win32 "$T/$1-win32" "${B32[@]}"; R32=$?
cp -f redist/Win64/WebView2Loader.dll data/blocklist-hosts.txt "$T/$1-win64/" 2>/dev/null
echo "RESULTADO win64=$R64 win32=$R32"
