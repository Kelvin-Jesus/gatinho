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

# Assinatura ad-hoc: o macOS lembra da permissão de Acessibilidade por assinatura.
codesign --force --sign - "$APP"
echo "Pronto: $(pwd)/$APP"
