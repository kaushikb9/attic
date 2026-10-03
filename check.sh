#!/bin/sh
# Verify Attic: unit + flow tests, then the app bundle builds and renders.
# No Photos access and no real photos: everything runs on a synthetic library.
set -e
cd "$(dirname "$0")"
out=$(scripts/test.sh 2>&1) || { echo "$out" | grep -E "✘|error:" | head -20; echo "check: tests failed"; exit 1; }
echo "$out" | grep "Test run"
CONFIG=debug scripts/build-app.sh >/dev/null
plutil -lint dist/Attic.app/Contents/Info.plist >/dev/null
T=$(mktemp -d)
dist/Attic.app/Contents/MacOS/Attic --make-fixture "$T/fixture" >/dev/null
dist/Attic.app/Contents/MacOS/Attic --snapshot "$T/shots" "$T/fixture" | grep -q "rendered nothing" && { echo "check: a section rendered nothing"; exit 1; }
n=$(ls "$T/shots" | wc -l | tr -d ' ')
[ "$n" -eq 7 ] || { echo "check: expected 7 snapshots, got $n in $T/shots"; exit 1; }
# The real window, after the actions that have broken it before.
swift scripts/window-check.swift dist/Attic.app "$T/fixture" "section:marked,confirm-all,delete"
rm -f "$T/fixture/deleted.json"
swift scripts/window-check.swift dist/Attic.app "$T/fixture" "section:retakes"
# The first section on launch draws the demo's one duplicate group.
dist/Attic.app/Contents/MacOS/Attic --make-demo "$T/demo" >/dev/null
swift scripts/window-check.swift dist/Attic.app "$T/demo" "" --expect "1 group" --reject "No duplicates left"
# Every control, used through the accessibility API on fresh demo libraries.
swift scripts/e2e.swift dist/Attic.app
scripts/public-check.sh
echo "check: all green (snapshots in $T/shots)"
