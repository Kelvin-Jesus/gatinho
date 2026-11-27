#!/bin/bash
# Compila e monta Gatinho.app (precisa só das Command Line Tools, sem Xcode).
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Gatinho"

APP="Gatinho.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Gatinho"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Gatinho</string>
  <key>CFBundleDisplayName</key><string>Gatinho</string>
  <key>CFBundleIdentifier</key><string>local.gatinho.desktopcat</string>
  <key>CFBundleExecutable</key><string>Gatinho</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# O macOS guarda a permissão de Acessibilidade pela assinatura. Com o certificado local
# "Gatinho Dev" ela fica igual a cada build; sem ele (CI, outra máquina), cai na ad hoc,
# que muda a cada build e obriga a dar a permissão de novo.
ID=$(security find-identity -p codesigning 2>/dev/null | awk '/"Gatinho Dev"/ {print $2; exit}')
if [ -n "$ID" ]; then
  codesign --force --sign "$ID" --identifier local.gatinho.desktopcat "$APP"
else
  echo "Aviso: sem o certificado \"Gatinho Dev\" (rode ./certificado-local.sh); usando assinatura ad hoc."
  codesign --force --sign - "$APP"
fi

# ./build.sh --install: troca o app em /Applications e abre de novo.
if [ "${1:-}" = "--install" ]; then
  pkill -x Gatinho 2>/dev/null && sleep 0.5 || true
  rm -rf "/Applications/$APP"
  ditto "$APP" "/Applications/$APP"
  open "/Applications/$APP"
  echo "Instalado e aberto: /Applications/$APP"
else
  echo "Pronto: $(pwd)/$APP  (use ./build.sh --install para instalar em /Applications)"
fi
