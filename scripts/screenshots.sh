#!/bin/sh
# Regenerate the README screenshots in docs/screenshots from the illustrated
# demo library (no real photos). Needs Screen Recording for the terminal.
set -e
cd "$(dirname "$0")/.."
CONFIG=debug scripts/build-app.sh >/dev/null
BIN=dist/Attic.app/Contents/MacOS/Attic
LIB=$(mktemp -d)/demo
"$BIN" --make-demo "$LIB" >/dev/null
mkdir -p docs/screenshots
shot() {  # name, steps
  # Visit another section first: the first section shown can render stale
  # (intermittent; see AGENTS.md, Known issues).
  swift scripts/capture.swift "$BIN" "$LIB" "light,size:1280x800,section:marked,$2" "docs/screenshots/$1.png" >/dev/null
  sips -Z 1600 "docs/screenshots/$1.png" >/dev/null
  echo "screenshots: $1"
}
shot duplicates "section:duplicates"
shot retakes "section:retakes"
shot best-of "section:bestOf"
shot marked "confirm-all,section:marked"
