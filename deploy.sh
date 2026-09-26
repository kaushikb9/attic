#!/bin/sh
# Build a release Attic.app and install it to ~/Applications. Refuses on red.
set -e
cd "$(dirname "$0")"
[ -n "$SKIP_CHECK" ] || ./check.sh
scripts/build-app.sh >/dev/null
mkdir -p ~/Applications
if pgrep -f "Applications/Attic.app/Contents/MacOS/Attic" >/dev/null; then  # yours, not test copies
  echo "deploy: Attic is open. Quit it first (it may be mid-review), then run ./deploy.sh again."
  exit 1
fi
rm -rf ~/Applications/Attic.app
cp -R dist/Attic.app ~/Applications/Attic.app
echo "deploy: installed ~/Applications/Attic.app ($(git rev-parse --short HEAD 2>/dev/null || echo uncommitted))"
