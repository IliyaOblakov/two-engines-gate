#!/usr/bin/env bash
# Usage: bash uninstall.sh   (same PREFIX as the install, default ~/.local)
# Removes exactly the files and folders install.sh listed in its manifest. A file that was changed
# after the install is kept and reported, and so is any folder that is no longer empty. When
# anything is kept, the manifest stays too, so a later run can finish the job.
set -uo pipefail
PREFIX="${PREFIX:-$HOME/.local}"
case "$PREFIX" in /*) ;; *) PREFIX="$PWD/$PREFIX" ;; esac
manifest="$PREFIX/share/two-engines-gate/install-manifest"
[ -f "$manifest" ] || { echo "uninstall: no install found at $PREFIX (no $manifest)" >&2; exit 1; }
left=0 folders=()
keep() { echo "uninstall: kept $1" >&2; left=1; }
while read -r kind rest; do
  if [ "$kind" = D ]; then folders+=("$rest"); continue; fi
  [ "$kind" = F ] || { keep "$manifest, it has an unreadable line"; continue; }
  hash="${rest%% *}" file="${rest#* }"
  [ -e "$file" ] || continue
  if [ "$(git hash-object "$file")" != "$hash" ]; then keep "$file, it changed after the install"
  elif ! rm -f "$file" || [ -e "$file" ]; then keep "$file, it could not be removed"; fi
done < "$manifest"
if [ "$left" = 0 ]; then rm -f "$manifest" || keep "$manifest"; fi
for (( i=${#folders[@]}-1; i>=0; i-- )); do
  [ -d "${folders[i]}" ] || continue
  rmdir "${folders[i]}" 2>/dev/null || keep "${folders[i]}, it is not empty"
done
if [ "$left" = 0 ]; then echo "uninstalled: every file and folder the install created is removed"; exit 0; fi
echo "uninstall: done, with the items above kept" >&2
exit 1
