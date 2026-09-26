#!/bin/sh
# Build dist/Attic-<version>.dmg: the app plus an Applications link to drag onto.
# Version = latest v* tag (v0.1.0 -> 0.1.0), or 0.0.0 with no tag.
# Publishing is separate and manual: gh release create v<version> dist/Attic-<version>.dmg
set -e
cd "$(dirname "$0")"
[ -n "$SKIP_CHECK" ] || ./check.sh
TAG=$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || echo v0.0.0)
export VERSION=${TAG#v}
scripts/build-app.sh >/dev/null
scripts/public-check.sh --app   # the release build itself must be clean
STAGE=$(mktemp -d)/Attic
mkdir -p "$STAGE"
cp -R dist/Attic.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
DMG=dist/Attic-$VERSION.dmg
rm -f "$DMG"
hdiutil create -volname "Attic $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
hdiutil verify "$DMG" >/dev/null
echo "release: $DMG ($(du -h "$DMG" | cut -f1)), version $VERSION"
