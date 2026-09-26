#!/bin/sh
# Regenerate the README screenshots in docs/screenshots from the illustrated
# demo library (no real photos). Needs Screen Recording for the terminal.
set -e
cd "$(dirname "$0")/.."
CONFIG=debug scripts/build-app.sh >/dev/null
LIB=$(mktemp -d)/demo
dist/Attic.app/Contents/MacOS/Attic --make-demo "$LIB" >/dev/null
mkdir -p docs/screenshots
shot() {  # name, steps
  swift scripts/window-check.swift dist/Attic.app "$LIB" "light,size:1280x800,$2" --save "docs/screenshots/$1.png" >/dev/null
  sips -Z 1600 "docs/screenshots/$1.png" >/dev/null
  echo "screenshots: $1"
}
shot duplicates "section:duplicates"
shot retakes "section:retakes"
shot best-of "section:bestOf"
shot marked "confirm-all,section:marked"
