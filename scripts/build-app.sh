#!/bin/sh
# Build Attic.app into dist/. No Xcode needed: SwiftPM binary + Info.plist +
# icon + ad-hoc signature (Photos permission is tied to the bundle id).
set -e
cd "$(dirname "$0")/.."
CONFIG=${CONFIG:-release}
# -file-prefix-map: source paths baked into the binary (for crash messages)
# read "./Sources/..." rather than the builder's home folder.
PREFIX="-Xswiftc -file-prefix-map -Xswiftc $(pwd)=."
# Quiet on success; on failure, show the compiler's output (it goes to
# stdout) instead of leaving the previous dist/Attic.app looking current.
out=$(swift build -c "$CONFIG" --product Attic $PREFIX 2>&1) || { echo "$out" | grep -E "error|warning: unre" | head -20; echo "build-app: swift build failed"; exit 1; }
BIN=$(swift build -c "$CONFIG" $PREFIX --show-bin-path)/Attic
APP=dist/Attic.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Attic"
# Release builds drop their symbol tables (about half the binary); the
# symbols stay beside it in dist/Attic.dSYM for reading crash reports.
if [ "$CONFIG" = release ]; then
  rm -rf dist/Attic.dSYM
  dsymutil "$BIN" -o dist/Attic.dSYM 2>/dev/null
  strip -S -x "$APP/Contents/MacOS/Attic"
fi
# Version from git: the latest v* tag (v0.1.2 -> 0.1.2), with "-dev" when the
# code has moved past it. release.sh insists on an exact tag instead.
if [ -z "$VERSION" ]; then
  TAG=$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || echo v0.0.0)
  VERSION=${TAG#v}
  git describe --tags --exact-match --match 'v*' >/dev/null 2>&1 || VERSION="$VERSION-dev"
fi
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
