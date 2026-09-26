#!/bin/sh
# Build (and with --publish, release) the DMG for the tagged commit.
#   git tag -a v0.1.2 -m "<what changed>" && ./release.sh   # build dist/Attic-0.1.2.dmg and dist/Attic.dmg
#   ./release.sh --publish                    # also push main + tag and create the GitHub release
# Refuses unless HEAD is exactly a v* tag and the tree is clean, so a DMG's
# version always names the code inside it.
set -e
cd "$(dirname "$0")"
TAG=$(git describe --tags --exact-match --match 'v*' 2>/dev/null) || {
  echo "release: HEAD is not tagged. Tag it first: git tag -a v<next version> -m \"<what changed>\""; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "release: uncommitted changes; commit them first"; exit 1; }
export VERSION=${TAG#v}
# An annotated tag's message is the release's "What's new"; check it before building.
NEW=""
[ "$(git cat-file -t "$TAG")" = tag ] && NEW="$(git tag -l --format='%(contents)' "$TAG" | sed '/^-----BEGIN/,$d')"
[ "$1" != "--publish" ] || [ -n "$NEW" ] || {
  echo "release: $TAG has no message. Retag with one: git tag -f -a $TAG -m \"<what changed>\""; exit 1; }
[ -n "$SKIP_CHECK" ] || ./check.sh
scripts/build-app.sh >/dev/null
scripts/public-check.sh --app   # the release build itself must be clean
STAGE=$(mktemp -d)/Attic
mkdir -p "$STAGE"
cp -R dist/Attic.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
DMG=dist/Attic-$VERSION.dmg
rm -f "$DMG" dist/Attic.dmg
hdiutil create -volname "Attic $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
hdiutil verify "$DMG" >/dev/null
cp "$DMG" dist/Attic.dmg   # stable name: .../releases/latest/download/Attic.dmg
echo "release: $DMG ($(du -h "$DMG" | cut -f1)), version $VERSION"

if [ "$1" = "--publish" ]; then
  git push -q origin main
  git push -q origin "$TAG"
  gh release create "$TAG" "$DMG" dist/Attic.dmg --title "Attic $VERSION" --notes-file - <<NOTES
## What's new

$NEW

## Install

Download **Attic.dmg**, open it and drag Attic to Applications. Needs macOS 15 or later on Apple Silicon.

Attic isn't notarized yet: the first time you open it, go to System Settings › Privacy & Security and click **Open Anyway**.
NOTES
  echo "release: published $TAG"
fi
