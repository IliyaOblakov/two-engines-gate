#!/usr/bin/env bash
# Usage: GATE_CMD="<your test command>" gate.sh [repo]   (default: the current directory)
# Runs the test command on a clean checkout and writes the pass record .ai/tests/<HEAD>.pass only
# after a clean pass on that exact commit. The record is removed before the run and stays removed
# when the command fails, when HEAD moves, when the run leaves changed or untracked files, and
# when the run shows that no test ran (so a run of zero tests is not a pass).
# Env: GATE_CMD        the command to run, through bash -c, from the repository root (required)
#      GATE_COUNT_RE   a bash regex for the lines that report tests; group 1 is the count on
#                      that line (an empty or missing group 1 counts as one) and the counts
#                      are added up. Unset: the run fails when its output is empty or has a
#                      known zero-test summary line, and other output passes.
#      GATE_MIN_TESTS  the fewest tests the count must reach (default 1; above 1 needs
#                      GATE_COUNT_RE); 0 turns every test count check off
# Exit: the test command's status; 1 for a refused run, too few tests or an unrecorded pass.
set -uo pipefail
case "${1:-}" in -h|--help) sed -n '2,14p' "$0"; exit 0 ;; esac
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
min="${GATE_MIN_TESTS:-1}" count_re="${GATE_COUNT_RE:-}"
[[ "$min" =~ ^[0-9]{1,9}$ ]] || die "GATE_MIN_TESTS must be a whole number, got '$min'"
if [ -n "$count_re" ]; then [[ "" =~ $count_re ]]; [ $? -ne 2 ] || die "GATE_COUNT_RE is not a valid regex"
elif [ "$min" -gt 1 ]; then die "GATE_MIN_TESTS above 1 needs GATE_COUNT_RE to count the tests"; fi
# Summary lines of runs where no test ran (none found, or every test filtered out or skipped).
# One such line fails the run, also when another command in GATE_CMD did run tests.
# go test and cargo test print a zero line for each package or target that has no tests, even
# when others ran, so they need GATE_COUNT_RE (see the README).
zero=(
  'no tests ran in [0-9]' '^[= ]*[0-9]+ (skipped|deselected)(, [0-9]+ (skipped|deselected|warnings?))* in [0-9]' # pytest
  '^Ran 0 tests in '                                                   # unittest
  '^([^ ]+ )?(tests|pass) 0$' '^1\.\.0( |$)'                            # node --test (TAP and spec)
  '^ *0 passing \('                                                    # mocha
  '^ *No tests found, exiting' '^Tests: +[0-9]+ (skipped|todo), ([0-9]+ (skipped|todo), )*[0-9]+ total' # Jest
  '^ *No test files found, exiting' '^ *Tests +(no tests|[0-9]+ (skipped|todo)( \| [0-9]+ (skipped|todo))* \()' # Vitest
)
zero_re="$(IFS='|'; echo "${zero[*]}")"
too_few() { # prints why the run reported too few tests; silent when it reported enough
  local text line c n=0
  [ "$min" -gt 0 ] || return 0
  [ -s "$log" ] || { echo "the test command printed nothing, so no test count"; return 0; }
  # Drop carriage returns and terminal colour and cursor codes so the patterns see plain lines.
  text="$(sed -e $'s/\r$//' -e $'s/\e\\[[0-9;?]*[A-Za-z]//g' "$log")" || { echo "cannot read the log $log"; return 0; }
  while IFS= read -r line; do
    if [ -z "$count_re" ]; then
      if [[ "$line" =~ $zero_re ]]; then echo "the output shows a run of zero tests: $line"; return 0; fi
    elif [[ "$line" =~ $count_re ]]; then
      c="${BASH_REMATCH[1]:-1}"
      [[ "$c" =~ ^[0-9]{1,9}$ ]] || { echo "GATE_COUNT_RE group 1 matched '$c', not a number"; return 0; }
      n=$((n + 10#$c))
    fi
  done <<< "$text" || { echo "cannot read the log $log"; return 0; }
  [ -z "$count_re" ] || [ "$n" -ge "$min" ] || echo "the output reports $n tests, fewer than GATE_MIN_TESTS=$min"
}
clean || die "REFUSED: uncommitted changes or untracked files (or git status failed); commit or remove them first"
echo "gate: running '$GATE_CMD' on ${head:0:12}"
bash -c "$GATE_CMD" > "$log" 2>&1
status=$?
if [ "$status" -eq 0 ]; then
  if [ "$(git rev-parse HEAD)" != "$head" ]; then echo "gate: HEAD moved during the run" >&2; status=1
  elif ! clean; then echo "gate: the run left changed or untracked files (or git status failed)" >&2; status=1
  else
    why="$(too_few)" || why="${why:-the test count check failed}"
    [ -z "$why" ] || { echo "gate: $why; set GATE_COUNT_RE or GATE_MIN_TESTS (README)" >&2; status=1; }
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
