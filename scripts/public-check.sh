#!/bin/sh
# Fail if anything personal is in a tracked file or in any commit. Patterns come
# from .public-denylist (one extended regex per line, case-insensitive), which is
# git-ignored so the list itself never goes public.
cd "$(dirname "$0")/.."
LIST=.public-denylist
[ -f "$LIST" ] || { echo "public-check: skipped (no $LIST)"; exit 0; }
bad=0
while IFS= read -r pat; do
  case "$pat" in ''|'#'*) continue ;; esac
  hits=$(git grep -I -n -i -E -e "$pat" -- . ':!.public-denylist' 2>/dev/null | head -5)
  if [ -n "$hits" ]; then echo "public-check: /$pat/ in tracked files:"; echo "$hits" | sed 's/^/    /'; bad=1; fi
  hist=$(git log --all -p --format='commit %h' 2>/dev/null | grep -i -E -e "$pat" | head -3)
  if [ -n "$hist" ]; then echo "public-check: /$pat/ in git history:"; echo "$hist" | cut -c1-100 | sed 's/^/    /'; bad=1; fi
done < "$LIST"
# With --app: the built release app too (strings in the binary and plist).
# Debug builds keep a source path and never ship, so check.sh doesn't pass it.
if [ "$1" = "--app" ]; then
  while IFS= read -r pat; do
    case "$pat" in ''|'#'*) continue ;; esac
    hit=$( { strings -a dist/Attic.app/Contents/MacOS/Attic; cat dist/Attic.app/Contents/Info.plist; } | grep -i -E -e "$pat" | head -2)
    if [ -n "$hit" ]; then echo "public-check: /$pat/ in dist/Attic.app:"; echo "$hit" | sed 's/^/    /'; bad=1; fi
  done < "$LIST"
fi
[ $bad -eq 0 ] && echo "public-check: clean ($(grep -cv '^\s*\(#\|$\)' "$LIST") patterns: files, history${1:+, built app})"
exit $bad
