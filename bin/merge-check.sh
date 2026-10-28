#!/usr/bin/env bash
# Usage: merge-check.sh [repo]   (default: the current directory)
# Says whether the checked-out commit may be merged. It refuses unless the checkout is clean (no
# changed or untracked files, no tracked file flagged skip-worktree or assume-unchanged), gate.sh
# recorded a pass for this exact commit, and review.sh saved an ACCEPT for this exact commit from a
# reviewer that is not the builder. It never merges and makes no network calls: merge with git once
# it passes. A local guard against merging the wrong commit, not a security boundary.
# Exit: 0 may merge, 1 refused.
set -uo pipefail
case "${1:-}" in -h|--help) sed -n '2,8p' "$0"; exit 0 ;; esac
refuse() { echo "merge-check: REFUSED: $*" >&2; exit 1; }
cd "${1:-.}" || exit 1
root="$(git rev-parse --show-toplevel 2>/dev/null)" || refuse "not a git repository"
cd "$root" || exit 1
head="$(git rev-parse --verify HEAD 2>/dev/null)" || refuse "no commit"
short="${head:0:12}"
flagged() { # lists tracked files marked skip-worktree or assume-unchanged, which git status never shows
  local rec name flag n=0 ended=0              # git ls-files -v: S = skip-worktree, a lowercase letter = assume-unchanged
  while IFS= read -r -d '' rec; do             # NUL-separated records; END after a successful git can never equal a record ("<tag> <name>")
    [ "$rec" != END ] || { ended=1; continue; }
    case "${rec:0:1}" in S) flag=skip-worktree ;; [[:lower:]]) flag=assume-unchanged ;; *) continue ;; esac
    name="${rec:2}"; n=$((n + 1))
    [ "$n" -gt 1 ] || echo "files that git status does not show are flagged, so changes to them would go unseen:" >&2
    printf '  %s: "%s"\n' "$flag" "${name//[[:cntrl:]]/?}" >&2
  done < <(git ls-files -v -z -- . ':(exclude).ai' && printf 'END\0')
  [ "$ended" -eq 1 ] || return 2
  [ "$n" -eq 0 ] || echo "clear a flag with: git update-index --no-skip-worktree -- <file>  or  git update-index --no-assume-unchanged -- <file>" >&2
  [ "$n" -eq 0 ]
}
status="$(git status --porcelain --untracked-files=all -- . ':(exclude).ai')" || refuse "git status failed"
[ -z "$status" ] || refuse "uncommitted changes or untracked files"
flagged || refuse "files flagged skip-worktree or assume-unchanged (or git ls-files failed)"
record=".ai/tests/$head.pass"
[ -f "$record" ] || refuse "no test pass record for $short; run gate.sh"
[ "$(sed -n 's/^Head: //p' "$record")" = "$head" ] || refuse "the pass record $record is not for $head"
verdict=".ai/reviews/$short.md"
[ -f "$verdict" ] || refuse "no review verdict for $short; run review.sh"
[ "$(sed -n 's/^Head: //p' "$verdict" | head -n 1)" = "$head" ] || refuse "the verdict $verdict is not for $head"
builder="$(sed -n 's/^Builder: //p' "$verdict" | head -n 1)"
reviewer="$(sed -n 's/^Reviewer: //p' "$verdict" | head -n 1)"
[ -n "$builder" ] && [ -n "$reviewer" ] && [ "$builder" != "$reviewer" ] \
  || refuse "the verdict for $short does not name two different engines"
[ "$(grep -c '^Verdict:' "$verdict")" -eq 1 ] && grep -qE '^Verdict: *ACCEPT *$' "$verdict" \
  || refuse "the verdict for $short is not a single ACCEPT"
echo "merge-check: OK: $short has a test pass and an ACCEPT from $reviewer (builder $builder)"
