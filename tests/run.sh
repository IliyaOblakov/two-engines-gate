#!/usr/bin/env bash
# Usage: bash tests/run.sh   Runs every check offline, in temporary folders, with the stand-in reviewer.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
while IFS= read -r v; do unset "$v"; done < <(compgen -e | grep -E '^(GIT_|STANDIN_|REVIEW|BUILDER$|GATE_CMD$)' || true)
tmp="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmp"' EXIT
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null HOME="$tmp/home" TMPDIR="$tmp/tmp"
export GIT_AUTHOR_NAME=Tester GIT_AUTHOR_EMAIL=tester@example.com GIT_COMMITTER_NAME=Tester GIT_COMMITTER_EMAIL=tester@example.com
mkdir -p "$HOME" "$TMPDIR" "$tmp/stand-in"
for e in claude codex; do ln -s "$ROOT/examples/stand-in-reviewer.sh" "$tmp/stand-in/$e"; done
export PATH="$tmp/stand-in:$PATH"
pass=0 fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $*"; }
want() { # want <exit> <label> <command...>
  local code="$1" label="$2"; shift 2
  "$@" > "$tmp/out" 2>&1; local got=$?
  if [ "$got" = "$code" ]; then ok; else bad "$label: exit $got, expected $code"; sed 's/^/  | /' "$tmp/out"; fi
}
has() { grep -q -- "$2" "$1" && ok || bad "$3"; }

echo "== syntax"
while IFS= read -r f; do want 0 "bash -n $f" bash -n "$f"; done < <(cd "$ROOT" && find . -name '*.sh' -not -path './.git/*' | sort | sed "s|^\.|$ROOT|")

echo "== content"
or_phrase="Claude Code"" or ""Codex"
if grep -rnP '[\x{2013}\x{2014}\x{0400}-\x{04FF}]|/home/[a-z]|/Users/[A-Za-z]|\b\d{1,3}(\.\d{1,3}){3}\b|brain\.' "$ROOT" --exclude-dir=.git; then
  bad "dash, Cyrillic, personal path, IP address or brain URL found"; else ok; fi
if grep -rn "$or_phrase" "$ROOT" --exclude-dir=.git; then bad "write Claude Code and Codex"; else ok; fi

echo "== demo in both directions"
for b in claude codex; do
  other=codex; [ "$b" = codex ] && other=claude
  want 0 "demo BUILDER=$b" env BUILDER="$b" bash "$ROOT/demo.sh"
  has "$tmp/out" "Reviewer: $other" "demo BUILDER=$b: the reviewer is not $other"
  [ "$(grep -c 'REFUSED' "$tmp/out")" = 4 ] && ok || bad "demo BUILDER=$b: expected four refusals"
done

echo "== review.sh exit codes"
repo="$tmp/repo"
mkdir -p "$repo" && cd "$repo" && git init -q -b main && printf '.ai/\n' > .gitignore && echo one > a.txt
git add -A && git commit -qm "chore: first" && git switch -qc work && echo two >> a.txt && git commit -qam "feat: second line"
head="$(git rev-parse HEAD)"; v=".ai/reviews/${head:0:12}.md"
R="$ROOT/bin/review.sh"
want 0 "accept" env STANDIN_ANSWER=accept STANDIN_PROMPT_COPY="$tmp/prompt" "$R"
has "$v" "^Head: $head" "verdict has no Head line"; has "$v" "^Reviewer: codex" "default reviewer is not codex"
has "$tmp/prompt" "^+two" "the prompt lacks the diff"; has "$tmp/prompt" "feat: second line" "the prompt lacks the commits"
want 0 "accept, BUILDER=codex" env BUILDER=codex STANDIN_ANSWER=accept "$R"
has "$v" "^Reviewer: claude" "BUILDER=codex did not make claude the reviewer"
want 2 "changes required" env STANDIN_ANSWER=changes "$R"
want 1 "no verdict line" env STANDIN_ANSWER=none "$R"
[ ! -e "$v" ] && ok || bad "a run without a verdict left a verdict file"
want 0 "accept again" env STANDIN_ANSWER=accept "$R"
want 1 "reviewer fails" env STANDIN_ANSWER=fail "$R"
[ ! -e "$v" ] && ok || bad "a failed run left the earlier verdict"
want 1 "two verdict lines" env STANDIN_ANSWER=two "$R"
want 1 "files changed during review" env STANDIN_TOUCH="$repo/new.txt" "$R"; rm -f "$repo/new.txt"
want 1 "same engine twice" env BUILDER=claude REVIEWER=claude "$R"
want 1 "unknown builder" env BUILDER=other "$R"
want 1 "claude without --restricted" env BUILDER=codex STANDIN_NO_RESTRICTED=1 "$R"
echo dirty >> a.txt; want 1 "dirty tree" "$R"; git checkout -q a.txt
want 1 "HEAD is the base" env REVIEW_BASE=HEAD "$R"

echo "== gate.sh"
G="$ROOT/bin/gate.sh"; rec=".ai/tests/$head.pass"
want 1 "no GATE_CMD" "$G"
want 0 "passing command" env GATE_CMD="true" "$G"; [ -f "$rec" ] && ok || bad "no pass record after a pass"
want 3 "failing command" env GATE_CMD="exit 3" "$G"; [ ! -e "$rec" ] && ok || bad "the pass record survived a failure"
want 1 "command leaves an untracked file" env GATE_CMD="touch stray.txt" "$G"; rm -f stray.txt
[ ! -e "$rec" ] && ok || bad "a run with an untracked file wrote a pass record"

echo "== merge-check.sh"
M="$ROOT/bin/merge-check.sh"
env GATE_CMD=true "$G" >/dev/null 2>&1; env STANDIN_ANSWER=accept "$R" >/dev/null 2>&1
want 0 "pass and accept" "$M"
sed -i 's/^Builder: claude/Builder: codex/' "$v"; want 1 "builder equals reviewer" "$M"
env STANDIN_ANSWER=changes "$R" >/dev/null 2>&1; want 1 "changes required" "$M"
env STANDIN_ANSWER=accept "$R" >/dev/null 2>&1; echo three >> a.txt; git commit -qam "fix: third line"
cp "$v" ".ai/reviews/$(git rev-parse --short=12 HEAD).md"; env GATE_CMD=true "$G" >/dev/null 2>&1
want 1 "verdict copied from an older commit" "$M"

echo "== install and uninstall on a scratch HOME"
snap() { (cd "$1" && find . -printf '%y %m %p\n' | sort && find . -type f | sort | while read -r f; do echo "$f $(git hash-object "$f")"; done); }
for setup in empty with-bin; do
  h="$tmp/home-$setup"; mkdir -p "$h"
  [ "$setup" = with-bin ] && mkdir -p "$h/.local/bin" && echo keep > "$h/.local/bin/other-tool"
  snap "$h" > "$tmp/before"
  want 0 "install ($setup)" env HOME="$h" bash "$ROOT/install.sh"
  want 0 "installed command runs ($setup)" "$h/.local/bin/two-engines-merge-check" --help
  [ -x "$h/.local/share/two-engines-gate/bin/review.sh" ] && ok || bad "review.sh not installed ($setup)"
  want 1 "second install refused ($setup)" env HOME="$h" bash "$ROOT/install.sh"
  want 0 "uninstall ($setup)" env HOME="$h" bash "$ROOT/uninstall.sh"
  snap "$h" > "$tmp/after"
  cmp -s "$tmp/before" "$tmp/after" && ok || { bad "HOME differs after uninstall ($setup)"; diff "$tmp/before" "$tmp/after"; }
done
h="$tmp/home-conflict"; mkdir -p "$h/.local/bin" && echo mine > "$h/.local/bin/two-engines-gate"
snap "$h" > "$tmp/before"
want 1 "install refuses an existing file" env HOME="$h" bash "$ROOT/install.sh"
snap "$h" > "$tmp/after"; cmp -s "$tmp/before" "$tmp/after" && ok || bad "a refused install changed HOME"
h="$tmp/home-edited"; mkdir -p "$h"
env HOME="$h" bash "$ROOT/install.sh" >/dev/null 2>&1; echo "# edited" >> "$h/.local/share/two-engines-gate/review-prompt.md"
want 1 "uninstall keeps an edited file" env HOME="$h" bash "$ROOT/uninstall.sh"
[ -f "$h/.local/share/two-engines-gate/review-prompt.md" ] && ok || bad "uninstall removed an edited file"

echo
echo "passed $pass, failed $fail"
[ "$fail" = 0 ]
