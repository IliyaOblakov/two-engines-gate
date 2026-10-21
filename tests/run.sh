#!/usr/bin/env bash
# Usage: bash tests/run.sh   Runs every check offline, in temporary folders, with the stand-in reviewer.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
while IFS= read -r v; do unset "$v"; done < <(compgen -e | grep -E '^(GIT_|STANDIN_|REVIEW|BUILDER$|GATE_(CMD|MIN_TESTS|COUNT_RE)$|PREFIX$|KEEP$|DEMO_REAL$)' || true)
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
in_dir() { local d="$1"; shift; (cd "$d" && "$@"); }
has() { grep -q -- "$2" "$1" && ok || bad "$3"; }

echo "== syntax"
while IFS= read -r f; do want 0 "bash -n $f" bash -n "$f"; done < <(cd "$ROOT" && find . -name '*.sh' -not -path './.git/*' | sort | sed "s|^\.|$ROOT|")

echo "== content"
files() { # tracked files in a clone, otherwise every file outside .git and .ai
  (cd "$ROOT" && { git ls-files -z 2>/dev/null || find . -type f -not -path './.git/*' -not -path './.ai/*' -print0; })
}
scan() { # scan <label> <grep args...>: a match or a grep error is a failure
  local list=() f rc
  while IFS= read -r -d '' f; do list+=("$f"); done < <(files)
  (cd "$ROOT" && grep -n "${@:2}" -- "${list[@]}"); rc=$?
  case "$rc" in 1) ok ;; 0) bad "$1" ;; *) bad "$1: grep failed ($rc)" ;; esac
}
scan "dash, Cyrillic, personal path, IP address or brain URL found" -P -e '[\x{2013}\x{2014}\x{0400}-\x{04FF}]|/home/[a-z]|/Users/[A-Za-z]|\b\d{1,3}(\.\d{1,3}){3}\b|brain\.'
scan "write Claude Code and Codex" -F -e "Claude Code"" or ""Codex"

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
want 1 "ACCEPT plus an unknown verdict line" env STANDIN_ANSWER=odd "$R"
mkdir -p sub && touch sub/.keep && git add sub && git commit -qm "chore: add a folder"
head="$(git rev-parse HEAD)"; v=".ai/reviews/${head:0:12}.md"
want 0 "run from a subfolder" in_dir sub env STANDIN_ANSWER=accept "$R"
[ -f "$v" ] && [ ! -e sub/.ai ] && ok || bad "a run from a subfolder did not write to the repository root"
cp .git/index "$tmp/index"; echo broken > .git/index
want 1 "review with a broken index" "$R"; want 1 "gate with a broken index" env GATE_CMD=true "$ROOT/bin/gate.sh"
want 1 "merge-check with a broken index" "$ROOT/bin/merge-check.sh"; cp "$tmp/index" .git/index
if [ "$(id -u)" != 0 ]; then
  echo x > "$tmp/locked.md"; chmod 000 "$tmp/locked.md"
  want 1 "unreadable prompt" env REVIEW_PROMPT="$tmp/locked.md" "$R"
fi
want 1 "files changed during review" env STANDIN_TOUCH="$repo/new.txt" "$R"; rm -f "$repo/new.txt"
want 1 "same engine twice" env BUILDER=claude REVIEWER=claude "$R"
want 1 "unknown builder" env BUILDER=other "$R"
want 1 "claude without --restricted" env BUILDER=codex STANDIN_NO_RESTRICTED=1 "$R"
echo dirty >> a.txt; want 1 "dirty tree" "$R"; git checkout -q a.txt
want 1 "HEAD is the base" env REVIEW_BASE=HEAD "$R"

echo "== gate.sh"
G="$ROOT/bin/gate.sh"; rec=".ai/tests/$head.pass"
want 1 "no GATE_CMD" "$G"
want 0 "passing command" env GATE_CMD="echo ok" "$G"; [ -f "$rec" ] && ok || bad "no pass record after a pass"
want 3 "failing command" env GATE_CMD="exit 3" "$G"; [ ! -e "$rec" ] && ok || bad "the pass record survived a failure"
env GATE_CMD="echo ok" "$G" >/dev/null 2>&1; want 1 "rerun without GATE_CMD" "$G"
[ ! -e "$rec" ] && ok || bad "a rerun without GATE_CMD kept the old pass record"
want 1 "command leaves an untracked file" env GATE_CMD="touch stray.txt" "$G"; rm -f stray.txt
[ ! -e "$rec" ] && ok || bad "a run with an untracked file wrote a pass record"

echo "== gate.sh: a run of zero tests is not a pass"
zt() { # zt <exit> <label> <output, printf %b> [VAR=value...]: gate.sh on a command that prints <output>
  local code="$1" label="$2"; printf '%b' "$3" > "$tmp/zt.txt"; shift 3
  want "$code" "$label" env GATE_CMD="cat '$tmp/zt.txt'" "$@" "$G"
  if [ "$code" = 0 ]; then [ -f "$rec" ] && ok || bad "$label: no pass record"
  else [ ! -e "$rec" ] && ok || bad "$label: a pass record was written"; fi
}
zt 1 "empty output" ""
zt 1 "pytest, no tests" "\n===== no tests ran in 0.01s =====\n"
zt 1 "unittest, no tests" "Ran 0 tests in 0.000s\r\n\r\nNO TESTS RAN\r\n"
zt 1 "node --test, no tests" "TAP version 13\n1..0\n# tests 0\n# pass 0\n"
zt 1 "mocha, no tests" "\n  0 passing (2ms)\n"
zt 1 "Jest, no tests" "No tests found, exiting with code 0\n"
zt 1 "Vitest, no tests" "\n No test files found, exiting with code 0\n"
zt 1 "node --test spec reporter, no tests" "\xe2\x84\xb9 tests 0\n\xe2\x84\xb9 pass 0\n"
zt 1 "pytest, every test deselected" "==== 2 deselected in 0.01s ====\n"
zt 1 "node --test, every test skipped" "# tests 1\n# pass 0\n# skipped 1\n"
zt 1 "Jest, every test skipped" "Tests:       2 skipped, 2 total\n"
zt 1 "Vitest, every test skipped" "      Tests  2 skipped (2)\n"
zt 1 "coloured mocha, no tests" "\e[92m \e[0m\e[32m 0 passing\e[0m\e[90m (2ms)\e[0m\n"
zt 1 "one command ran tests, another ran none" "  1 passing (2ms)\n  0 passing (1ms)\n"
zt 0 "summaries with tests that ran" "  10 passing (5ms)\nRan 10 tests in 0.01s\n1 passed, 1 deselected in 0.01s\n# tests 2\n# pass 1\nTests:       1 skipped, 1 passed, 2 total\n      Tests  1 passed | 1 skipped (2)\n\e[32m  3 passing\e[0m\n"
zt 0 "zero-test check off" "" GATE_MIN_TESTS=0
count='^test result: ok\. ([0-9]+) passed'
zt 0 "counts added up" "test result: ok. 2 passed; 0 failed\ntest result: ok. 0 passed; 0 failed\n" GATE_COUNT_RE="$count"
zt 1 "count of zero" "test result: ok. 0 passed; 0 failed\r\n" GATE_COUNT_RE="$count"
zt 1 "no counted line" "all good\n" GATE_COUNT_RE="$count"
zt 1 "fewer than GATE_MIN_TESTS" "test result: ok. 2 passed\n" GATE_COUNT_RE="$count" GATE_MIN_TESTS=3
zt 0 "a match without a group counts one" "--- PASS: TestA\n--- PASS: TestB\n" GATE_COUNT_RE='^--- PASS' GATE_MIN_TESTS=2
zt 1 "group 1 is not a number" "tests: many\n" GATE_COUNT_RE='^tests: (.*)'
zt 1 "bad GATE_MIN_TESTS" "ok\n" GATE_MIN_TESTS=one
zt 1 "GATE_MIN_TESTS above 1 without GATE_COUNT_RE" "  5 passing (2ms)\n" GATE_MIN_TESTS=2
[ "$(id -u)" = 0 ] || zt 1 "unreadable log" "ok\n" GATE_CMD="cat '$tmp/zt.txt'; chmod 000 .ai/tests/*.log"; rm -f .ai/tests/*.log
zt 1 "invalid GATE_COUNT_RE" "ok\n" GATE_COUNT_RE='('

echo "== merge-check.sh"
M="$ROOT/bin/merge-check.sh"
env GATE_CMD="echo ok" "$G" >/dev/null 2>&1; env STANDIN_ANSWER=accept "$R" >/dev/null 2>&1
want 0 "pass and accept" "$M"
sed -i 's/^Builder: claude/Builder: codex/' "$v"; want 1 "builder equals reviewer" "$M"
env STANDIN_ANSWER=changes "$R" >/dev/null 2>&1; want 1 "changes required" "$M"
env STANDIN_ANSWER=accept "$R" >/dev/null 2>&1; echo three >> a.txt; git commit -qam "fix: third line"
cp "$v" ".ai/reviews/$(git rev-parse --short=12 HEAD).md"; env GATE_CMD="echo ok" "$G" >/dev/null 2>&1
want 1 "verdict copied from an older commit" "$M"

echo "== install and uninstall on a scratch HOME"
snap() { (cd "$1" && find . -printf '%y %m %p\n' | sort && find . -type f | sort | while read -r f; do echo "$f $(git hash-object "$f")"; done); }
for setup in empty with-bin with-share; do
  h="$tmp/home-$setup"; mkdir -p "$h"
  [ "$setup" = with-bin ] && mkdir -p "$h/.local/bin" && echo keep > "$h/.local/bin/other-tool"
  [ "$setup" = with-share ] && mkdir -p "$h/.local/share/two-engines-gate/bin" && echo x > "$h/.local/share/two-engines-gate/bin/other.sh"
  snap "$h" > "$tmp/before"
  want 0 "install ($setup)" env HOME="$h" PREFIX="$h/.local" bash "$ROOT/install.sh"
  want 0 "installed command runs ($setup)" "$h/.local/bin/two-engines-merge-check" --help
  [ -x "$h/.local/share/two-engines-gate/bin/review.sh" ] && ok || bad "review.sh not installed ($setup)"
  want 1 "second install refused ($setup)" env HOME="$h" PREFIX="$h/.local" bash "$ROOT/install.sh"
  want 0 "uninstall ($setup)" env HOME="$h" PREFIX="$h/.local" bash "$ROOT/uninstall.sh"
  snap "$h" > "$tmp/after"
  cmp -s "$tmp/before" "$tmp/after" && ok || { bad "HOME differs after uninstall ($setup)"; diff "$tmp/before" "$tmp/after"; }
done
h="$tmp/home-conflict"; mkdir -p "$h/.local/bin" && echo mine > "$h/.local/bin/two-engines-gate"
snap "$h" > "$tmp/before"
want 1 "install refuses an existing file" env HOME="$h" PREFIX="$h/.local" bash "$ROOT/install.sh"
snap "$h" > "$tmp/after"; cmp -s "$tmp/before" "$tmp/after" && ok || bad "a refused install changed HOME"
h="$tmp/home-edited"; mkdir -p "$h"
env HOME="$h" PREFIX="$h/.local" bash "$ROOT/install.sh" >/dev/null 2>&1; echo "# edited" >> "$h/.local/share/two-engines-gate/review-prompt.md"
want 1 "uninstall keeps an edited file" env HOME="$h" PREFIX="$h/.local" bash "$ROOT/uninstall.sh"
[ -f "$h/.local/share/two-engines-gate/review-prompt.md" ] && ok || bad "uninstall removed an edited file"
h="$tmp/home-odd"; mkdir -p "$h/odd \$(x)"
want 0 "install with a relative PREFIX holding odd characters" in_dir "$h" env HOME="$h" PREFIX='odd $(x)/p' bash "$ROOT/install.sh"
want 0 "wrapper runs from another folder" in_dir / "$h/odd \$(x)/p/bin/two-engines-gate" --help
want 0 "uninstall with the same relative PREFIX" in_dir "$h" env HOME="$h" PREFIX='odd $(x)/p' bash "$ROOT/uninstall.sh"
[ ! -e "$h/odd \$(x)/p" ] && ok || bad "uninstall left the relative PREFIX behind"
h="$tmp/home-space"; mkdir -p "$h/p"; snap "$h" > "$tmp/before"
want 0 "install into a PREFIX ending in a space" env HOME="$h" PREFIX="$h/p " bash "$ROOT/install.sh"
want 0 "uninstall from a PREFIX ending in a space" env HOME="$h" PREFIX="$h/p " bash "$ROOT/uninstall.sh"
snap "$h" > "$tmp/after"; cmp -s "$tmp/before" "$tmp/after" && ok || bad "a PREFIX ending in a space was not restored"
h="$tmp/home-extra"; mkdir -p "$h"
env HOME="$h" PREFIX="$h/.local" bash "$ROOT/install.sh" >/dev/null 2>&1; echo mine > "$h/.local/bin/other"
want 1 "uninstall keeps a folder with a foreign file" env HOME="$h" PREFIX="$h/.local" bash "$ROOT/uninstall.sh"
[ -f "$h/.local/share/two-engines-gate/install-manifest" ] && ok || bad "the manifest was lost while a folder was kept"
rm "$h/.local/bin/other"
want 0 "a second uninstall finishes the job" env HOME="$h" PREFIX="$h/.local" bash "$ROOT/uninstall.sh"
[ -z "$(ls -A "$h")" ] && ok || bad "the second uninstall left files behind"
h="$tmp/home-top"; mkdir -p "$h"
env HOME="$h" PREFIX="$h/.local" bash "$ROOT/install.sh" >/dev/null 2>&1; echo mine > "$h/.local/other"
want 1 "uninstall keeps PREFIX with a foreign file in it" env HOME="$h" PREFIX="$h/.local" bash "$ROOT/uninstall.sh"
grep -qx "D $h/.local/share" "$h/.local/share/two-engines-gate/install-manifest" && ok || bad "a recreated folder is missing from the manifest"
rm "$h/.local/other"
want 0 "a second uninstall removes every recreated folder" env HOME="$h" PREFIX="$h/.local" bash "$ROOT/uninstall.sh"
[ -z "$(ls -A "$h")" ] && ok || bad "the second uninstall left folders behind"
if [ "$(id -u)" != 0 ]; then
  h="$tmp/home-locked"; mkdir -p "$h/.local/bin"
  env HOME="$h" PREFIX="$h/.local" bash "$ROOT/install.sh" >/dev/null 2>&1; chmod 555 "$h/.local/bin"
  want 1 "uninstall reports files it cannot remove" env HOME="$h" PREFIX="$h/.local" bash "$ROOT/uninstall.sh"
  [ -f "$h/.local/share/two-engines-gate/install-manifest" ] && ok || bad "uninstall dropped the manifest after a failed removal"
  chmod 755 "$h/.local/bin"
fi
echo
echo "passed $pass, failed $fail"
[ "$fail" = 0 ]
