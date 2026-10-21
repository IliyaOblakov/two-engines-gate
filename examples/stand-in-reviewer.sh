#!/usr/bin/env bash
# Stand-in for the claude and codex CLIs, so demo.sh and tests/run.sh run without any model or account.
# Copy or link it as "claude" and "codex" in a folder at the front of PATH. It reads the prompt and
# answers from STANDIN_ANSWER: accept (default), changes, none (no verdict line), two (two verdict
# lines) or fail (exit 1). STANDIN_FINDING replaces the default finding text, STANDIN_TOUCH names a
# file to create during the review, STANDIN_PROMPT_COPY saves the prompt it received, and
# STANDIN_NO_RESTRICTED=1 leaves --restricted out of the claude help text.
set -uo pipefail
name="$(basename "$0")"
if [ "${1:-}" = --help ]; then
  echo "$name stand-in"
  [ "$name" = claude ] && [ "${STANDIN_NO_RESTRICTED:-0}" != 1 ] && echo "  --restricted"
  exit 0
fi
out=""
while [ $# -gt 0 ]; do
  [ "$1" = --output-last-message ] && { out="${2:-}"; shift; }
  shift
done
prompt="$(cat)"
[ -n "${STANDIN_PROMPT_COPY:-}" ] && printf '%s\n' "$prompt" > "$STANDIN_PROMPT_COPY"
[ -n "${STANDIN_TOUCH:-}" ] && echo touched > "$STANDIN_TOUCH"
finding="${STANDIN_FINDING:-should-fix, example.sh:1: a canned finding from the stand-in reviewer.}"
intro="Review by a stand-in for $name. No model was called; this answer is canned."
case "${STANDIN_ANSWER:-accept}" in
  accept) answer="$intro"$'\n\nVerdict: ACCEPT\n\nNo findings.' ;;
  changes) answer="$intro"$'\n\nVerdict: CHANGES REQUIRED\n\n'"- $finding" ;;
  none) answer="$intro"$'\n\nLooks fine overall.' ;;
  two) answer="$intro"$'\n\nVerdict: ACCEPT\nVerdict: CHANGES REQUIRED' ;;
  fail) echo "$name stand-in: simulated failure" >&2; exit 1 ;;
  *) echo "$name stand-in: unknown STANDIN_ANSWER" >&2; exit 1 ;;
esac
if [ "$name" = codex ]; then
  [ -n "$out" ] || { echo "codex stand-in: --output-last-message missing" >&2; exit 1; }
  printf '%s\n' "$answer" > "$out"
  echo "codex stand-in: review written"
else
  printf '%s\n' "$answer"
fi
