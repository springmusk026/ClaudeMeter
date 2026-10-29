#!/bin/zsh
# Build ClaudeMeter.app, install it to ~/Applications and launch it.
set -euo pipefail
cd "${0:A:h}"

APP=build/ClaudeMeter.app
rm -rf build
mkdir -p "$APP/Contents/MacOS"
swiftc -O -swift-version 5 -parse-as-library Sources/*.swift -o "$APP/Contents/MacOS/ClaudeMeter"
cp Info.plist "$APP/Contents/"

# App icon (rendered once from tools/make-icon.swift)
if [[ ! -f Resources/AppIcon.icns ]]; then
  tmp=$(mktemp -d)
  swift tools/make-icon.swift "$tmp/icon.png"
  mkdir "$tmp/AppIcon.iconset"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$tmp/icon.png" --out "$tmp/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) "$tmp/icon.png" --out "$tmp/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
  done
  mkdir -p Resources
  iconutil -c icns "$tmp/AppIcon.iconset" -o Resources/AppIcon.icns
  rm -rf "$tmp"
fi
mkdir -p "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - "$APP"

pkill -x ClaudeMeter 2>/dev/null || true
mkdir -p ~/Applications
rm -rf ~/Applications/ClaudeMeter.app
ditto "$APP" ~/Applications/ClaudeMeter.app
open ~/Applications/ClaudeMeter.app
echo "Installed ~/Applications/ClaudeMeter.app"
