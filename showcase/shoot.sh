#!/bin/sh
# Regenerate showcase/light.png and dark.png (1280×800, the window's content,
# no shadow) from the illustrated demo library. No real photos are involved.
# Needs Screen Recording for the terminal; the window opens in the background.
set -e
cd "$(dirname "$0")/.."
CONFIG=debug scripts/build-app.sh >/dev/null
LIB=$(mktemp -d)/demo
dist/Attic.app/Contents/MacOS/Attic --make-demo "$LIB" >/dev/null
for look in light dark; do
  swift scripts/window-check.swift dist/Attic.app "$LIB" "$look,size:1280x800,section:bestOf" --save-plain "showcase/$look.png" >/dev/null
  sips -z 800 1280 "showcase/$look.png" >/dev/null
  echo "showcase: $look.png"
done
