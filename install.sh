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
share="$PREFIX/share/two-engines-gate" manifest="$PREFIX/share/two-engines-gate/install-manifest"
die() { echo "install: $*" >&2; exit 1; }
command -v git >/dev/null || die "git is required"
sources=(bin/review.sh bin/gate.sh bin/merge-check.sh review-prompt.md)
declare -A cmd=([review]=review.sh [gate]=gate.sh [merge-check]=merge-check.sh)
targets=("$manifest")
for s in "${sources[@]}"; do [ -f "$HERE/$s" ] || die "missing $s; run from a full clone"; targets+=("$share/$s"); done
for c in "${!cmd[@]}"; do targets+=("$PREFIX/bin/two-engines-$c"); done
for t in "${targets[@]}"; do
  [ ! -e "$t" ] && [ ! -L "$t" ] || die "$t already exists; nothing was changed (run uninstall.sh first, or set PREFIX)"
done
created=()
make_dir() { # creates a folder and its missing parents, remembering each one, outermost first
  local d="$1" missing=()
  while [ ! -d "$d" ]; do missing=("$d" ${missing[@]+"${missing[@]}"}); d="$(dirname "$d")"; done
  for d in ${missing[@]+"${missing[@]}"}; do mkdir "$d" || return 1; created+=("$d"); done
}
undo() { [ -f "$manifest" ] && PREFIX="$PREFIX" bash "$HERE/uninstall.sh" >/dev/null 2>&1
  for (( i=${#created[@]}-1; i>=0; i-- )); do rmdir "${created[i]}" 2>/dev/null; done; die "$1; the partial install was undone"; }
make_dir "$share/bin" && make_dir "$PREFIX/bin" || undo "cannot create folders under $PREFIX"
: > "$manifest" || undo "cannot write $manifest"
for d in ${created[@]+"${created[@]}"}; do printf 'dir\t%s\n' "$d" >> "$manifest" || undo "cannot write $manifest"; done
add() { # records a created file with its git blob hash
  printf 'file\t%s\t%s\n' "$1" "$(git hash-object "$1")" >> "$manifest" || undo "cannot write $manifest"
}
for s in "${sources[@]}"; do
  cp "$HERE/$s" "$share/$s" || undo "cannot copy $s"
  add "$share/$s"
done
chmod +x "$share"/bin/*.sh || undo "cannot make the scripts executable"
for c in "${!cmd[@]}"; do
  w="$PREFIX/bin/two-engines-$c"
  printf '#!/usr/bin/env bash\nexec "%s" "$@"\n' "$share/bin/${cmd[$c]}" > "$w" && chmod +x "$w" || undo "cannot write $w"
  add "$w"
done
echo "installed: two-engines-review, two-engines-gate and two-engines-merge-check in $PREFIX/bin"
case ":$PATH:" in *":$PREFIX/bin:"*) ;; *) echo "note: $PREFIX/bin is not on PATH; add it, or call the scripts by their full path" ;; esac
echo "undo with: bash uninstall.sh"
