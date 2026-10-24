#!/bin/bash
# Builds PulseDock.app (universal: Apple silicon + Intel), then PulseDock.dmg and PulseDock.zip in ./dist
# Usage: ./scripts/build-app.sh            (version 1.0.0)
#        VERSION=1.2.0 ./scripts/build-app.sh
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.0.0}"
BUILD="${BUILD:-$(date +%Y%m%d%H%M)}"
ARCHS="${ARCHS:---arch arm64 --arch x86_64}"

echo "==> Building PulseDock $VERSION ($BUILD)"
# shellcheck disable=SC2086
swift build -c release $ARCHS
# shellcheck disable=SC2086
BIN_DIR="$(swift build -c release $ARCHS --show-bin-path)"

APP="dist/PulseDock.app"
rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/PulseDock" "$APP/Contents/MacOS/PulseDock"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"
printf "APPL????" > "$APP/Contents/PkgInfo"

echo "==> Icon"
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z $d $d Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "==> Signing (ad-hoc)"
codesign --force --deep --options runtime --sign - "$APP"
codesign --verify --verbose=2 "$APP"

echo "==> Packaging"
ditto -c -k --keepParent "$APP" dist/PulseDock.zip
DMG_ROOT="$(mktemp -d)/PulseDock"
mkdir -p "$DMG_ROOT"
cp -R "$APP" "$DMG_ROOT/"
ln -s /Applications "$DMG_ROOT/Applications"
hdiutil create -volname "PulseDock" -srcfolder "$DMG_ROOT" -ov -format UDZO dist/PulseDock.dmg >/dev/null

echo "==> Done"
ls -lh dist
