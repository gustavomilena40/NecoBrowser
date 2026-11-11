#!/bin/bash
# Prepara (e, com --enviar, publica) uma versão do NecoBrowser no GitHub Releases.
#   bash tools/publicar.sh 0.2.0            -> sobe a versão no .dproj, compila Release Win64/Win32,
#                                               confere a versão dos exes e gera os .sha256
#   bash tools/publicar.sh 0.2.0 --enviar   -> o mesmo + tag v0.2.0 + push da tag + release no GitHub
# Os navegadores instalados procuram a release mais nova e se atualizam sozinhos
# (src/core/Neco.Core.Updater.pas). Precisa de: gh autenticado (gh auth login) para --enviar.
# Saída: %TEMP%\NecoBuild\release-v<versao>\ (NecoBrowser-win64.exe, -win32.exe e .sha256).
set -e
V="$1"
ENVIAR="$2"
if ! [[ "$V" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "uso: bash tools/publicar.sh <X.Y.Z> [--enviar]"; exit 1
fi
P="$(cd "$(dirname "$0")/.." && pwd)"
T="$TEMP/NecoBuild"
C=/c/Users/user02/.agent-bridge/skills/delphi-fmx-visual/compilar.py
D="$T/release-v$V"
cd "$P"

if [ "$ENVIAR" = "--enviar" ]; then
  gh auth status >/dev/null 2>&1 || { echo "gh não está autenticado: rode 'gh auth login'"; exit 1; }
  if git rev-parse "v$V" >/dev/null 2>&1; then echo "a tag v$V já existe"; exit 1; fi
fi

# 1. Versão no .dproj (vale para o recurso de versão do exe, lido pelo atualizador).
python -I - "$V" <<'PY'
import re, sys
v = sys.argv[1].split('.')
p = 'NecoBrowser.dproj'
s = open(p, 'rb').read().decode('utf-8')
s = re.sub(r'FileVersion=[0-9.]+', 'FileVersion=%s.%s.%s.0' % tuple(v), s)
s = re.sub(r'ProductVersion=[0-9.]+', 'ProductVersion=%s.%s.%s.0' % tuple(v), s)
s = re.sub(r'<VerInfo_MajorVer>\d+</VerInfo_MajorVer>', '<VerInfo_MajorVer>%s</VerInfo_MajorVer>' % v[0], s)
s = re.sub(r'<VerInfo_MinorVer>\d+</VerInfo_MinorVer>', '<VerInfo_MinorVer>%s</VerInfo_MinorVer>' % v[1], s)
# Release não existe no .dproj enquanto for 0: entra ao lado do MajorVer.
if '<VerInfo_Release>' in s:
    s = re.sub(r'<VerInfo_Release>\d+</VerInfo_Release>', '<VerInfo_Release>%s</VerInfo_Release>' % v[2], s)
else:
    s = re.sub(r'([ \t]*)(<VerInfo_MajorVer>\d+</VerInfo_MajorVer>)',
               lambda m: m.group(1) + m.group(2) + '\r\n' + m.group(1) + '<VerInfo_Release>%s</VerInfo_Release>' % v[2],
               s, count=1)
open(p, 'wb').write(s.encode('utf-8'))
PY
echo "versão no .dproj: $V"

# 1b. O exe pega a versão do NecoBrowser.res (o da IDE), não do .dproj. O msbuild gera um .res
# com a versão nova, mas sem o ícone: gera numa cópia e transplanta só o bloco de versão.
cp -f NecoBrowser.dproj NecoBrowser_ver.dproj
cat > "$T/versao.bat" <<EOF
@echo off
call "C:\\Program Files (x86)\\Embarcadero\\Studio\\37.0\\bin\\rsvars.bat"
cd /d "$(cygpath -w "$P")"
msbuild NecoBrowser_ver.dproj /t:BuildVersionResource /p:Config=Release /p:Platform=Win64 /nologo /v:minimal
EOF
mkdir -p "$T"
cmd //c "$(cygpath -w "$T/versao.bat")" > "$T/versao.log" 2>&1 || true
rm -f NecoBrowser_ver.dproj NecoBrowser_ver.vrc
if [ ! -f NecoBrowser_ver.res ]; then
  echo "ERRO: msbuild não gerou o .res da versão (ver $T/versao.log)"; exit 1
fi
python -I "$P/tools/versao_res.py" NecoBrowser_ver.res NecoBrowser.res
rm -f NecoBrowser_ver.res

# 2. Compila Release nos dois alvos (fontes normalizados como no build.sh).
python -I "$P/tools/bomcrlf.py" NecoBrowser.dpr NecoBrowser.dproj src/core/*.pas src/engine/*.pas \
  src/ui/*.pas src/ui/*.fmx | grep -v " ok$" || true
rm -rf "$D"; mkdir -p "$D"
for PL in Win64 Win32; do
  L=$(echo "$PL" | tr 'A-Z' 'a-z')
  python -I -X utf8 $C NecoBrowser.dproj $PL "$T/release-v$V-$L" --config Release \
    | tee "$T/release-v$V-$L.resumo"
  grep -q "EXIT=0 " "$T/release-v$V-$L.resumo" || { echo "ERRO: build $PL falhou"; exit 1; }
  cp -f "$T/release-v$V-$L/NecoBrowser.exe" "$D/NecoBrowser-$L.exe"
done

# 3. A versão gravada no exe tem que ser a pedida; senão o atualizador baixaria de novo sempre.
for L in win64 win32; do
  F=$(powershell -NoProfile -Command "(Get-Item '$(cygpath -w "$D/NecoBrowser-$L.exe")').VersionInfo.FileVersion" | tr -d '\r')
  if [ "$F" != "$V.0" ]; then
    echo "ERRO: NecoBrowser-$L.exe saiu com a versão '$F' (esperado $V.0). Nada foi publicado."
    exit 1
  fi
done

# 4. Hash de cada exe (o atualizador só troca se o download bater com ele).
cd "$D"
for L in win64 win32; do
  sha256sum "NecoBrowser-$L.exe" > "NecoBrowser-$L.exe.sha256"
done
ls -l "$D"
cd "$P"

if [ "$ENVIAR" != "--enviar" ]; then
  echo "pronto em $D (nada enviado). Para publicar: commit do .dproj e rode de novo com --enviar"
  exit 0
fi

# 5. Tag e release.
git tag "v$V"
git push origin "v$V"
gh release create "v$V" "$D"/NecoBrowser-win64.exe "$D"/NecoBrowser-win64.exe.sha256 \
  "$D"/NecoBrowser-win32.exe "$D"/NecoBrowser-win32.exe.sha256 \
  --title "NecoBrowser $V" --generate-notes
echo "publicada: v$V"
