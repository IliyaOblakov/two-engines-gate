#!/usr/bin/env bash
# Usage: bash install.sh   (from a clone of this repository)
# Copies the three scripts and the review prompt to PREFIX/share/two-engines-gate and adds the
# commands two-engines-review, two-engines-gate and two-engines-merge-check to PREFIX/bin.
# PREFIX defaults to ~/.local. It never overwrites: if any target already exists it stops before
# changing anything. Every file and folder it creates is listed in a manifest, and uninstall.sh
# removes exactly those, so the folder is left as it was. Nothing outside PREFIX is touched.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${PREFIX:-$HOME/.local}"
case "$PREFIX" in /*) ;; *) PREFIX="$PWD/$PREFIX" ;; esac
share="$PREFIX/share/two-engines-gate" manifest="$PREFIX/share/two-engines-gate/install-manifest"
die() { echo "install: $*" >&2; exit 1; }
command -v git >/dev/null || die "git is required"
scripts=(review.sh gate.sh merge-check.sh)
names=(two-engines-review two-engines-gate two-engines-merge-check)
targets=("$manifest" "$share/review-prompt.md")
[ -f "$HERE/review-prompt.md" ] || die "missing review-prompt.md; run from a full clone"
for i in 0 1 2; do
  [ -f "$HERE/bin/${scripts[i]}" ] || die "missing bin/${scripts[i]}; run from a full clone"
  targets+=("$share/bin/${scripts[i]}" "$PREFIX/bin/${names[i]}")
done
for t in "${targets[@]}"; do
  [ ! -e "$t" ] && [ ! -L "$t" ] || die "$t already exists; nothing was changed (run uninstall.sh first, or set PREFIX)"
done
new_dirs=() writing=""
undo() {
  [ -n "$writing" ] && rm -f "$writing"
  [ -f "$manifest" ] && PREFIX="$PREFIX" bash "$HERE/uninstall.sh" >/dev/null 2>&1
  for (( i=${#new_dirs[@]}-1; i>=0; i-- )); do rmdir "${new_dirs[i]}" 2>/dev/null; done
  die "$1; the partial install was undone"
}
ensure_dir() { # walks the absolute path from the root down and creates each missing part
  local part path=""
  IFS=/ read -ra parts <<< "${1#/}"
  for part in "${parts[@]}"; do
    path="$path/$part"
    [ -d "$path" ] && continue
    mkdir "$path" || return 1
    new_dirs+=("$path")
  done
}
ensure_dir "$share/bin" && ensure_dir "$PREFIX/bin" || undo "cannot create folders under $PREFIX"
writing="$manifest"
for d in ${new_dirs[@]+"${new_dirs[@]}"}; do echo "D $d"; done > "$manifest" || undo "cannot write $manifest"
writing=""
place() { # place <target> <command producing the content>: writes a new file and records it
  local target="$1"; shift
  writing="$target"
  "$@" > "$target" || undo "cannot write $target"
  echo "F $(git hash-object "$target") $target" >> "$manifest" || undo "cannot write $manifest"
  writing=""
}
wrapper() { printf '#!/usr/bin/env bash\nexec %q "$@"\n' "$1"; }
place "$share/review-prompt.md" cat "$HERE/review-prompt.md"
for i in 0 1 2; do
  place "$share/bin/${scripts[i]}" cat "$HERE/bin/${scripts[i]}"
  chmod +x "$share/bin/${scripts[i]}" || undo "cannot make ${scripts[i]} executable"
  place "$PREFIX/bin/${names[i]}" wrapper "$share/bin/${scripts[i]}"
  chmod +x "$PREFIX/bin/${names[i]}" || undo "cannot make ${names[i]} executable"
done
echo "installed: ${names[*]} in $PREFIX/bin"
case ":$PATH:" in *":$PREFIX/bin:"*) ;; *) echo "note: $PREFIX/bin is not on PATH; add it, or call the scripts by their full path" ;; esac
echo "undo with: bash uninstall.sh"
