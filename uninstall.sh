#!/usr/bin/env bash
# Usage: bash uninstall.sh   (same PREFIX as the install, default ~/.local)
# Removes exactly the files and folders install.sh listed in its manifest. A file that was changed
# after the install is kept and reported, and so is any folder that is no longer empty.
set -uo pipefail
PREFIX="${PREFIX:-$HOME/.local}"
manifest="$PREFIX/share/two-engines-gate/install-manifest"
[ -f "$manifest" ] || { echo "uninstall: no install found at $PREFIX (no $manifest)" >&2; exit 1; }
kept=0 dirs=()
while IFS=$'\t' read -r kind path hash; do
  case "$kind" in
    dir) dirs+=("$path") ;;
    file)
      if [ ! -e "$path" ]; then continue
      elif [ "$(git hash-object "$path")" = "$hash" ]; then rm -f "$path"
      else echo "uninstall: kept $path, it changed after the install" >&2; kept=1; fi ;;
  esac
done < "$manifest"
[ "$kept" = 1 ] || rm -f "$manifest"
for (( i=${#dirs[@]}-1; i>=0; i-- )); do
  [ -d "${dirs[i]}" ] || continue
  rmdir "${dirs[i]}" 2>/dev/null || { echo "uninstall: kept ${dirs[i]}, it is not empty" >&2; kept=1; }
done
[ "$kept" = 0 ] && echo "uninstalled: every file and folder the install created is removed" && exit 0
echo "uninstall: done, with the items above kept" >&2
exit 1
