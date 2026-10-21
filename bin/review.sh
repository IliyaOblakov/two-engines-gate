#!/usr/bin/env bash
# Usage: review.sh [repo]   (default: the current directory)
# Asks the engine that did not write the code for a read-only review of the checked-out commit and
# saves its verdict as .ai/reviews/<first 12 characters of HEAD>.md. The verdict comes from the
# reviewer's final message only, and only when the reviewer exited 0 and the checkout did not change.
# Any earlier verdict for this commit is removed first, so a failed run never leaves an old one behind.
# Env: BUILDER      claude (default) or codex: the engine that wrote the code
#      REVIEWER     optional; must be the other engine
#      REVIEW_BASE  base of the reviewed range (default origin/main, else main)
#      REVIEW_MODEL optional model name passed to the reviewer CLI (default: the CLI's own default)
#      REVIEW_PROMPT prompt file (default: review-prompt.md next to this script's folder)
# Exit: 0 Verdict: ACCEPT, 2 Verdict: CHANGES REQUIRED, 1 no verdict (failed run, refused, bad setting).
set -uo pipefail
case "${1:-}" in -h|--help) sed -n '2,13p' "$0"; exit 0 ;; esac
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
prompt_file="${REVIEW_PROMPT:-$HERE/review-prompt.md}"
case "$prompt_file" in /*) ;; *) prompt_file="$PWD/$prompt_file" ;; esac
die() { echo "review: $*" >&2; exit 1; }
cd "${1:-.}" || exit 1
root="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not a git repository"
cd "$root" || exit 1
head="$(git rev-parse --verify HEAD 2>/dev/null)" || die "no commit to review"
dir=".ai/reviews" verdict=".ai/reviews/${head:0:12}.md"
rm -f "$verdict"; [ ! -e "$verdict" ] || die "cannot remove the earlier verdict $verdict"

BUILDER="${BUILDER:-claude}"
case "$BUILDER" in
  claude) other=codex ;;
  codex) other=claude ;;
  *) die "BUILDER must be claude or codex, not '$BUILDER'" ;;
esac
REVIEWER="${REVIEWER:-$other}"
[ "$REVIEWER" = "$other" ] || die "the reviewer must be the other engine ($other), not '$REVIEWER'"
[ -f "$prompt_file" ] || die "prompt file not found: $prompt_file"

clean() { # fails on changed or untracked files outside .ai/, and when git status itself fails
  local out; out="$(git status --porcelain --untracked-files=all -- . ':(exclude).ai')" && [ -z "$out" ]
}
clean || die "REFUSED: uncommitted changes or untracked files (or git status failed); commit or remove them first"
if [ -n "${REVIEW_BASE:-}" ]; then base="$REVIEW_BASE"
elif git rev-parse -q --verify origin/main >/dev/null; then base=origin/main
else base=main; fi
git rev-parse -q --verify "$base^{commit}" >/dev/null || die "base '$base' is not a commit here; set REVIEW_BASE"
[ "$(git rev-parse "$base")" != "$head" ] || die "HEAD is the base '$base': nothing to review"
command -v "$REVIEWER" >/dev/null || die "the $REVIEWER CLI is not on PATH"

mkdir -p "$dir" || die "cannot create $dir"
work="$(mktemp -d)" || die "cannot create a temporary folder"
trap 'rm -rf "$work"' EXIT
{
  cat "$prompt_file" &&
  printf '\n\n## Commits in %s..HEAD\n\n' "$base" &&
  git log --no-color --format='commit %H%nAuthor: %an <%ae>%n%n%B' "$base..HEAD" &&
  printf '\n## Diff %s...HEAD\n\n' "$base" &&
  git -c core.fsmonitor=false diff --no-color --no-ext-diff --no-textconv "$base...HEAD"
} > "$work/prompt" || die "cannot build the prompt"
model=(); [ -n "${REVIEW_MODEL:-}" ] && model=(--model "$REVIEW_MODEL")
log="$dir/${head:0:12}.log"
if [ "$REVIEWER" = codex ]; then
  codex exec -s read-only ${model[@]+"${model[@]}"} --color never \
    --output-last-message "$work/last" - < "$work/prompt" > "$log" 2>&1
  status=$?
else
  # stdin from /dev/null: with a terminal on stdin, claude --help can wait instead of exiting.
  claude --help < /dev/null 2>&1 | grep -q -- '--restricted' || die "this Claude Code has no --restricted flag; update it"
  claude -p "Do the review described on standard input." --restricted --strict-mcp-config \
    --permission-mode dontAsk ${model[@]+"${model[@]}"} --tools "Read,Grep,Glob" --allowedTools "Read,Grep,Glob" \
    --disallowedTools "Bash,Edit,MultiEdit,Write,NotebookEdit,WebFetch,WebSearch,Task,Agent" \
    < "$work/prompt" > "$work/last" 2> "$log"
  status=$?
fi
echo "$REVIEWER exit $status" >> "$log"
[ "$status" -eq 0 ] || die "REVIEW FAILED: $REVIEWER exited $status; no verdict for ${head:0:12} (log: $log)"
[ "$(git rev-parse HEAD)" = "$head" ] || die "REVIEW VOID: HEAD moved during the review"
clean || die "REVIEW VOID: files changed during the review (or git status failed)"
[ -s "$work/last" ] || die "NO VERDICT: $REVIEWER wrote no final message"
count="$(grep -c '^Verdict:' "$work/last")"
[ "$count" -eq 1 ] || die "NO VERDICT: the final message needs exactly one Verdict: line, found $count"
grep -qE '^Verdict: *(ACCEPT|CHANGES REQUIRED) *$' "$work/last" \
  || die "NO VERDICT: the Verdict: line must say ACCEPT or CHANGES REQUIRED"
{
  echo "Head: $head"
  echo "Base: $(git rev-parse "$base") ($base)"
  echo "Builder: $BUILDER"
  echo "Reviewer: $REVIEWER"
  echo "Date: $(date '+%F %H:%M %Z')"
  echo
  cat "$work/last"
  [ -z "$(tail -c 1 "$work/last")" ] || echo
} > "$work/report" || die "cannot write the report"
cp "$work/report" "$verdict.tmp" && mv -f "$verdict.tmp" "$verdict" || { rm -f "$verdict.tmp"; die "cannot save $verdict"; }
cat "$verdict"
echo "verdict file: $verdict"
grep -qE '^Verdict: *ACCEPT *$' "$work/last" && exit 0
exit 2
