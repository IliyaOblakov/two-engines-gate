#!/usr/bin/env bash
# Usage: bash demo.sh   One run of the loop on a throwaway repository in a temporary folder.
# A stand-in answers as the reviewer, so no model, account or network is used. The folder is
# removed at the end. Env: BUILDER (claude or codex, default claude), DEMO_REAL=1 calls the real
# reviewer CLI instead (it uses your normal login and usage), KEEP=1 keeps the folder.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILDER="${BUILDER:-claude}"
case "$BUILDER" in claude|codex) ;; *) echo "BUILDER must be claude or codex" >&2; exit 1 ;; esac
while IFS= read -r v; do unset "$v"; done < <(compgen -e | grep -E '^(GIT_|STANDIN_|REVIEW)' || true)
unset GATE_CMD
tmp="$(mktemp -d)" || exit 1
cleanup() { if [ "${KEEP:-0}" = 1 ]; then echo "kept: $tmp"; else rm -rf "$tmp"; fi; }
trap cleanup EXIT
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
export GIT_AUTHOR_NAME="Demo Author" GIT_AUTHOR_EMAIL="demo@example.com"
export GIT_COMMITTER_NAME="Demo Author" GIT_COMMITTER_EMAIL="demo@example.com"
export BUILDER GATE_CMD="bash test.sh"
if [ "${DEMO_REAL:-0}" = 1 ]; then
  echo "DEMO_REAL=1: the real reviewer CLI is called and its answers are not checked."
else
  mkdir -p "$tmp/home" "$tmp/tmp" "$tmp/stand-in"
  export HOME="$tmp/home" TMPDIR="$tmp/tmp" XDG_CONFIG_HOME="$tmp/home/.config"
  ln -s "$HERE/examples/stand-in-reviewer.sh" "$tmp/stand-in/claude"
  ln -s "$HERE/examples/stand-in-reviewer.sh" "$tmp/stand-in/codex"
  export PATH="$tmp/stand-in:$PATH"
fi
fails=0
step() { printf '\n== %s\n' "$1"; }
expect() { # expected exit, then the command
  local want="$1"; shift
  "$@"; local got=$?
  if [ "$got" = "$want" ]; then echo "(exit $got, as expected)"
  elif [ "${DEMO_REAL:-0}" = 1 ]; then echo "(exit $got)"
  else echo "UNEXPECTED: exit $got, expected $want"; fails=$((fails + 1)); fi
}
repo="$tmp/repo"
mkdir -p "$repo" && cd "$repo" || exit 1
git init -q -b main && printf '.ai/\n' > .gitignore
printf 'echo "demo project"\n' > README.txt
git add -A && git commit -qm "chore: start the demo project" || exit 1
git switch -qc feature
cat > sum.sh <<'CODE'
#!/usr/bin/env bash
total=0
for n in "${@:2}"; do total=$((total + n)); done
echo "$total"
CODE
printf '[ "$(bash sum.sh 0 4)" = 4 ] || { echo "sum 0 4 failed"; exit 1; }\necho "tests passed"\n' > test.sh
git add -A && git commit -qm "feat: add sum.sh" || exit 1
echo "Reviewer is the other engine: BUILDER=$BUILDER. Repository: a throwaway copy in a temp folder."

step "1. The $BUILDER builder committed sum.sh. Merge check before anything else"
expect 1 "$HERE/bin/merge-check.sh"
step "2. Tests pass on this commit (they miss the bug)"
expect 0 "$HERE/bin/gate.sh"
expect 1 "$HERE/bin/merge-check.sh"
step "3. Read-only review by the other engine"
export STANDIN_ANSWER=changes STANDIN_FINDING="blocker, sum.sh:3: the loop starts at the second argument, so 'bash sum.sh 3 4' prints 4, not 7. test.sh only checks 'sum 0 4', where the bug cannot show."
expect 2 "$HERE/bin/review.sh"
expect 1 "$HERE/bin/merge-check.sh"
step "4. The builder fixes it in a new commit. The old evidence does not carry over"
sed -i 's/"\${@:2}"/"$@"/' sum.sh
printf '[ "$(bash sum.sh 3 4)" = 7 ] || { echo "sum 3 4 failed"; exit 1; }\n' | cat - test.sh > test.new && mv test.new test.sh
git commit -qam "fix: sum.sh adds every argument" || exit 1
expect 1 "$HERE/bin/merge-check.sh"
step "5. Tests and a new review on the new commit"
expect 0 "$HERE/bin/gate.sh"
export STANDIN_ANSWER=accept
expect 0 "$HERE/bin/review.sh"
expect 0 "$HERE/bin/merge-check.sh"
step "6. Merge with git"
git switch -q main && git merge -q --ff-only feature && git log --oneline -n 3
echo
ls .ai/reviews/*.md .ai/tests/*.pass
if [ "$fails" -gt 0 ]; then echo "demo: $fails unexpected results" >&2; exit 1; fi
echo "demo: done"
