#!/bin/sh
# Build Attic.app into dist/. No Xcode needed: SwiftPM binary + Info.plist +
# icon + ad-hoc signature (Photos permission is tied to the bundle id).
set -e
cd "$(dirname "$0")/.."
CONFIG=${CONFIG:-release}
# -file-prefix-map: source paths baked into the binary (for crash messages)
# read "./Sources/..." rather than the builder's home folder.
PREFIX="-Xswiftc -file-prefix-map -Xswiftc $(pwd)=."
swift build -c "$CONFIG" --product Attic $PREFIX >/dev/null
BIN=$(swift build -c "$CONFIG" $PREFIX --show-bin-path)/Attic
APP=dist/Attic.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Attic"
# VERSION (e.g. 0.2.0) comes from release.sh; builds without it are dev builds.
VERSION=${VERSION:-0.0.0}
BUILD=$(git rev-list --count HEAD 2>/dev/null || echo 0)
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" scripts/Info.plist > "$APP/Contents/Info.plist"

# Icon: rendered from code, sized with sips, packed with iconutil.
ICONSET=$(mktemp -d)/Attic.iconset
mkdir -p "$ICONSET"
"$BIN" --make-icon "$ICONSET/icon_512x512@2x.png"
for s in 16 32 128 256 512; do
  sips -z $s $s "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2)); sips -z $d $d "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Attic.icns"

codesign --force --sign - --identifier app.attic.mac "$APP" >/dev/null 2>&1
echo "$APP"
