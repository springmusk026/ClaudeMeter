#!/bin/zsh
# Build ClaudeMeter.app, install it to ~/Applications and launch it.
# With --no-install, only build it into build/ (used by CI and releases).
set -euo pipefail
cd "${0:A:h}"

APP=build/ClaudeMeter.app
rm -rf build
mkdir -p "$APP/Contents/MacOS"
swiftc -O -swift-version 5 -parse-as-library Sources/*.swift Shared/*.swift -o "$APP/Contents/MacOS/ClaudeMeter"
cp Info.plist "$APP/Contents/"

# Widget extension: sandboxed, signed before the app that contains it
EXT="$APP/Contents/PlugIns/ClaudeMeterWidget.appex"
mkdir -p "$EXT/Contents/MacOS"
swiftc -O -swift-version 5 -parse-as-library -application-extension Widget/*.swift Shared/*.swift \
  -o "$EXT/Contents/MacOS/ClaudeMeterWidget"
cp Widget/Info.plist "$EXT/Contents/"
for key in CFBundleShortVersionString CFBundleVersion; do
  plutil -replace $key -string "$(plutil -extract $key raw Info.plist)" "$EXT/Contents/Info.plist"
done
codesign --force --sign - --entitlements Widget/Widget.entitlements "$EXT"

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

if [[ ${1:-} == --no-install ]]; then
  echo "Built $APP"
  exit 0
fi

pkill -x ClaudeMeter 2>/dev/null || true
mkdir -p ~/Applications
rm -rf ~/Applications/ClaudeMeter.app
ditto "$APP" ~/Applications/ClaudeMeter.app
open ~/Applications/ClaudeMeter.app
echo "Installed ~/Applications/ClaudeMeter.app"
