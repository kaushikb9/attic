#!/bin/sh
# swift test, with Swift Testing found on Macs that have only the Command Line
# Tools (no Xcode). With Xcode selected, this is plain `swift test`.
# Extra args (--filter …) pass through.
set -e
cd "$(dirname "$0")/.."
DEV=$(xcode-select -p)
case "$DEV" in
  */CommandLineTools)
    F="$DEV/Library/Developer/Frameworks"; L="$DEV/Library/Developer/usr/lib"
    exec swift test -Xswiftc -F -Xswiftc "$F" -Xlinker -F -Xlinker "$F" \
      -Xlinker -rpath -Xlinker "$F" -Xlinker -rpath -Xlinker "$L" "$@" ;;
esac
exec swift test "$@"
