#!/usr/bin/env bash
# Usage: GATE_CMD="<your test command>" gate.sh [repo]   (default: the current directory)
# Runs the test command on a clean checkout and writes the pass record .ai/tests/<HEAD>.pass only
# after a clean pass on that exact commit. The record is removed before the run and stays removed
# when the command fails, when HEAD moves or when the run leaves changed or untracked files.
# Env: GATE_CMD  the command to run, through bash -c, from the repository root (required)
# Exit: the test command's status; 1 for a refused run or a pass that could not be recorded.
set -uo pipefail
case "${1:-}" in -h|--help) sed -n '2,7p' "$0"; exit 0 ;; esac
die() { echo "gate: $*" >&2; exit 1; }
cd "${1:-.}" || exit 1
root="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not a git repository"
cd "$root" || exit 1
head="$(git rev-parse --verify HEAD 2>/dev/null)" || die "no commit to test"
clean() { # fails on changed or untracked files outside .ai/, and when git status itself fails
  local out; out="$(git status --porcelain --untracked-files=all -- . ':(exclude).ai')" && [ -z "$out" ]
}
dir=".ai/tests" record=".ai/tests/$head.pass" log=".ai/tests/${head:0:12}.log"
mkdir -p "$dir" || die "cannot create $dir"
rm -f "$record"; [ ! -e "$record" ] || die "cannot remove the earlier pass record $record"
[ -n "${GATE_CMD:-}" ] || die "set GATE_CMD to the test command, for example GATE_CMD='npm test'"
clean || die "REFUSED: uncommitted changes or untracked files (or git status failed); commit or remove them first"
echo "gate: running '$GATE_CMD' on ${head:0:12}"
bash -c "$GATE_CMD" > "$log" 2>&1
status=$?
if [ "$status" -eq 0 ]; then
  if [ "$(git rev-parse HEAD)" != "$head" ]; then echo "gate: HEAD moved during the run" >&2; status=1
  elif ! clean; then echo "gate: the run left changed or untracked files (or git status failed)" >&2; status=1
  fi
fi
if [ "$status" -eq 0 ]; then
  printf 'Head: %s\nCommand: %s\nDate: %s\n' "$head" "$GATE_CMD" "$(date '+%F %H:%M %Z')" > "$record.tmp" \
    && mv -f "$record.tmp" "$record" || { rm -f "$record.tmp"; die "cannot write $record"; }
  echo "gate: PASS on ${head:0:12}, record $record"
else
  rm -f "$record"
  tail -n 20 "$log" >&2
  echo "gate: FAIL (exit $status) on ${head:0:12}; no pass record; full log $log" >&2
fi
exit "$status"
