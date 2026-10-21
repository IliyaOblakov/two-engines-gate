#!/usr/bin/env bash
# Usage: bash uninstall.sh   (same PREFIX as the install, default ~/.local)
# Removes exactly the files and folders install.sh listed in its manifest. A file that was changed
# after the install is kept and reported, and so is any folder that is not empty. Whenever anything
# is kept, the manifest is rewritten with what is left, so a later run can finish the job.
set -uo pipefail
PREFIX="${PREFIX:-$HOME/.local}"
case "$PREFIX" in /*) ;; *) PREFIX="$PWD/$PREFIX" ;; esac
share="$PREFIX/share/two-engines-gate" manifest="$PREFIX/share/two-engines-gate/install-manifest"
[ -f "$manifest" ] || { echo "uninstall: no install found at $PREFIX (no $manifest)" >&2; exit 1; }
files=() hashes=() folders=() left_files=() left_dirs=()
while IFS= read -r line; do
  case "$line" in
    "D "*) folders+=("${line#D }") ;;
    "F "*) rest="${line#F }"; hashes+=("${rest%% *}"); files+=("${rest#* }") ;;
    *) echo "uninstall: $manifest has an unknown line; nothing was removed" >&2; exit 1 ;;
  esac
done < "$manifest"
kept() { echo "uninstall: kept $1" >&2; }
for i in "${!files[@]}"; do
  f="${files[i]}"
  [ -e "$f" ] || [ -L "$f" ] || continue
  if [ "$(git hash-object "$f")" != "${hashes[i]}" ]; then kept "$f, it changed after the install"
  elif rm -f "$f" && [ ! -e "$f" ]; then continue
  else kept "$f, it could not be removed"; fi
  left_files+=("F ${hashes[i]} $f")
done
for (( i=${#folders[@]}-1; i>=0; i-- )); do
  d="${folders[i]}"
  [ -d "$d" ] || continue
  # The manifest's own folder goes only when nothing else is left in it and nothing was kept.
  if [ "$d" = "$share" ] && [ ${#left_files[@]} -eq 0 ] && [ ${#left_dirs[@]} -eq 0 ] \
     && [ "$(ls -A "$d")" = install-manifest ]; then rm -f "$manifest"; fi
  rmdir "$d" 2>/dev/null || { kept "$d, it is not empty"; left_dirs=("D $d" ${left_dirs[@]+"${left_dirs[@]}"}); }
done
if [ ${#left_files[@]} -eq 0 ] && [ ${#left_dirs[@]} -eq 0 ]; then
  rm -f "$manifest"
  echo "uninstalled: every file and folder the install created is removed"; exit 0
fi
# Something is left: recreate the manifest's folder (only folders from the manifest can be missing
# on the way to it) and list every folder from the manifest that exists now, parent first.
mkdir -p "$share" || echo "uninstall: could not recreate $share" >&2
left_dirs=()
for d in "${folders[@]}"; do [ -d "$d" ] && left_dirs+=("D $d"); done
printf '%s\n' ${left_dirs[@]+"${left_dirs[@]}"} ${left_files[@]+"${left_files[@]}"} > "$manifest" \
  || echo "uninstall: could not rewrite $manifest" >&2
echo "uninstall: done, with the items above kept; run it again after dealing with them" >&2
exit 1
