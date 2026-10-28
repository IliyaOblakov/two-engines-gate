# two-engines-gate

A local review and merge gate for Claude Code and Codex. One engine writes the code; the other reviews the commit read-only and its verdict is saved under the exact commit it reviewed. The project's tests run on that same commit. `merge-check.sh` refuses unless HEAD has both a test pass and an ACCEPT.

Early: first public version 21 Oct 2026.

Requirements: bash 4 or newer and git. Real reviews also need the Claude Code and Codex CLIs, installed and logged in. The demo and the tests need neither CLI, no account and no network. `tests/run.sh` also needs GNU find and grep.

Platforms: tested on Linux, on Ubuntu 24.04 under WSL2 and on Debian 13, with bash 5.2. The tests and the demo also pass with bash 4.0, 4.2, 4.3 and 4.4 built from source on Linux. macOS is not tested: it ships bash 3.2, older than the bash 4 this project supports, so it needs a newer bash, for example from Homebrew.

Built on information gathered since the first Codex and Claude CLIs.

## Try it in a minute

```
git clone https://github.com/IliyaOblakov/two-engines-gate.git
cd two-engines-gate
bash demo.sh
BUILDER=codex bash demo.sh
```

The demo builds a throwaway repository in a temporary folder and walks through one change: a commit with a bug the tests miss, the merge check refusing, a CHANGES REQUIRED review, a fix commit whose old evidence no longer counts, then tests and an ACCEPT on the new commit and the merge. A stand-in answers as the reviewer, so no model is called. `DEMO_REAL=1 bash demo.sh` calls the real reviewer CLI instead. The folder is removed at the end (`KEEP=1` keeps it).

The lines below are copied from one run of `bash demo.sh` with the offline stand-in reviewer, whose answers are canned. Blank lines and the rest of the output are left out; all of it is under the collapsed heading below:

```
== 1. The claude builder committed sum.sh. Merge check before anything else
merge-check: REFUSED: no test pass record for 2cef9bbe04c3; run gate.sh
== 2. Tests pass on this commit (they miss the bug)
gate: PASS on 2cef9bbe04c3, record .ai/tests/2cef9bbe04c3dd4727d2455e07c0ec420ecec7af.pass
merge-check: REFUSED: no review verdict for 2cef9bbe04c3; run review.sh
== 3. Read-only review by the other engine
Verdict: CHANGES REQUIRED
- blocker, sum.sh:3: the loop starts at the second argument, so 'bash sum.sh 3 4' prints 4, not 7. test.sh only checks 'sum 0 4', where the bug cannot show.
merge-check: REFUSED: the verdict for 2cef9bbe04c3 is not a single ACCEPT
== 4. The builder fixes it in a new commit. The old evidence does not carry over
merge-check: REFUSED: no test pass record for 525000aeac20; run gate.sh
== 5. Tests and a new review on the new commit
gate: PASS on 525000aeac20, record .ai/tests/525000aeac2006842bc5de60fd03229f2f697203.pass
Verdict: ACCEPT
merge-check: OK: 525000aeac20 has a test pass and an ACCEPT from codex (builder claude)
```

`BUILDER=codex bash demo.sh` runs the same steps with the roles swapped. Its last merge check reads `merge-check: OK: 525000aeac20 has a test pass and an ACCEPT from claude (builder codex)` (commit hashes can differ between runs).

<details>
<summary>Output of one run of <code>bash demo.sh</code> (commit hashes and dates may differ between runs)</summary>

```
Reviewer is the other engine: BUILDER=claude. Repository: a throwaway copy in a temp folder.

== 1. The claude builder committed sum.sh. Merge check before anything else
merge-check: REFUSED: no test pass record for c8e3ca33697c; run gate.sh
(exit 1, as expected)

== 2. Tests pass on this commit (they miss the bug)
gate: running 'bash test.sh' on c8e3ca33697c
gate: PASS on c8e3ca33697c, record .ai/tests/c8e3ca33697c18c989363e2668c5160991999ef1.pass
(exit 0, as expected)
merge-check: REFUSED: no review verdict for c8e3ca33697c; run review.sh
(exit 1, as expected)

== 3. Read-only review by the other engine
Head: c8e3ca33697c18c989363e2668c5160991999ef1
Base: 3da6d9ffdd88068b253a28637099ea910044403f (main)
Builder: claude
Reviewer: codex
Date: 2026-10-21 17:29 EEST

Review by a stand-in for codex. No model was called; this answer is canned.

Verdict: CHANGES REQUIRED

- blocker, sum.sh:3: the loop starts at the second argument, so 'bash sum.sh 3 4' prints 4, not 7. test.sh only checks 'sum 0 4', where the bug cannot show.
verdict file: .ai/reviews/c8e3ca33697c.md
(exit 2, as expected)
merge-check: REFUSED: the verdict for c8e3ca33697c is not a single ACCEPT
(exit 1, as expected)

== 4. The builder fixes it in a new commit. The old evidence does not carry over
merge-check: REFUSED: no test pass record for db1d095eb939; run gate.sh
(exit 1, as expected)

== 5. Tests and a new review on the new commit
gate: running 'bash test.sh' on db1d095eb939
gate: PASS on db1d095eb939, record .ai/tests/db1d095eb939688006353bb7227b28bb1f38f146.pass
(exit 0, as expected)
Head: db1d095eb939688006353bb7227b28bb1f38f146
Base: 3da6d9ffdd88068b253a28637099ea910044403f (main)
Builder: claude
Reviewer: codex
Date: 2026-10-21 17:29 EEST

Review by a stand-in for codex. No model was called; this answer is canned.

Verdict: ACCEPT

No findings.
verdict file: .ai/reviews/db1d095eb939.md
(exit 0, as expected)
merge-check: OK: db1d095eb939 has a test pass and an ACCEPT from codex (builder claude)
(exit 0, as expected)

== 6. Merge with git once the merge check passes
db1d095 fix: sum.sh adds every argument
c8e3ca3 feat: add sum.sh
3da6d9f chore: start the demo project

.ai/reviews/c8e3ca33697c.md
.ai/reviews/db1d095eb939.md
.ai/tests/c8e3ca33697c18c989363e2668c5160991999ef1.pass
.ai/tests/db1d095eb939688006353bb7227b28bb1f38f146.pass
demo: done
```

</details>

## How it works

| Script | What it does | Writes |
|---|---|---|
| `bin/review.sh` | Sends the commits and the diff to the engine that did not write them, read-only. Takes the verdict from its final message only. | `.ai/reviews/<sha12>.md` |
| `bin/gate.sh` | Runs `GATE_CMD` on a clean checkout. Records a pass only when the command passed, left the checkout unchanged and did not report a run of zero tests (see below). | `.ai/tests/<sha>.pass` |
| `bin/merge-check.sh` | Refuses unless the checkout is clean and HEAD has a pass record and an ACCEPT from a reviewer that is not the builder. Never merges. | nothing |

Why the verdict is named after the commit: an ACCEPT for an older commit can quietly cover code nobody reviewed. A new commit needs a new review and a new test run. review.sh and gate.sh remove their earlier evidence for the commit before anything else, so a failed or refused run never leaves an old pass or ACCEPT behind.

Exit codes of review.sh: 0 for `Verdict: ACCEPT`, 2 for `Verdict: CHANGES REQUIRED`, 1 when there is no verdict (the reviewer failed, the final message held no single verdict line, the checkout changed during the review, or a setting was wrong).

## Install

From a clone, run `bash install.sh`. It copies the scripts and the review prompt to `~/.local/share/two-engines-gate` and adds `two-engines-review`, `two-engines-gate` and `two-engines-merge-check` to `~/.local/bin` (`PREFIX` changes `~/.local`). It stops without changing anything when one of those files already exists. `bash uninstall.sh` removes exactly what the install created; a file edited after the install, or a folder that also holds other files, is kept and reported, and running it again after dealing with those finishes the job.

No install is needed to use it: every script runs from the clone, for example `path/to/two-engines-gate/bin/review.sh`.

Add `.ai/` to the project's `.gitignore`. The scripts ignore changes under `.ai/` when they check for a clean checkout.

The clean check also refuses when a tracked file carries the `skip-worktree` or `assume-unchanged` flag, because `git status` does not show edits to such a file. All three scripts run `git ls-files -v` and refuse when a line starts with `S` (skip-worktree) or a lowercase letter (assume-unchanged). The message names each file and the flag, for example `skip-worktree: "src/config.txt"`. Clear a flag with `git update-index --no-skip-worktree -- <file>` or `git update-index --no-assume-unchanged -- <file>`. A file that has both flags is listed as assume-unchanged until you clear that one, then as skip-worktree. A sparse checkout sets skip-worktree on every tracked file outside its patterns, so it is refused whenever it leaves a file out. Tracked files under `.ai/` are not checked, like their changes.

## Use it with Claude Code and Codex

1. Paste `snippets/CLAUDE.md` into the project's `CLAUDE.md` and `snippets/AGENTS.md` into its `AGENTS.md`. They tell the builder to commit each change and stop, to leave `.ai/` alone and never to merge, and tell the reviewer to stay read-only.
2. The builder (Claude Code by default) writes a change and commits it on a branch.
3. Run the gate on that commit, from the repository:

```
GATE_CMD="npm test" two-engines-gate
BUILDER=claude two-engines-review
two-engines-merge-check && git switch main && git merge --ff-only <branch>
```

4. On CHANGES REQUIRED, the builder fixes every finding in a new commit, and step 3 runs again on the new commit.

`BUILDER=codex` flips the roles: Codex writes and Claude Code reviews. `REVIEW_BASE` sets the start of the reviewed range (default `origin/main`, else `main`). `REVIEW_MODEL` picks the reviewer's model. `docs/engines.md` has the exact reviewer calls, what each one can and cannot do, and the Codex config notes.

### A run of zero tests is not a pass

A test command can exit 0 without running a single test, for example when a file list or a filter selects nothing. gate.sh then refuses the pass (exit 1). With `GATE_COUNT_RE` unset it reads the summary lines of pytest, unittest, `node --test`, mocha, Jest and Vitest, adds up the tests that ran in all of them, and fails the run when its output is empty or the summaries add up to zero: no tests found (all six), or every test filtered out or skipped (pytest, `node --test`, mocha, Jest, Vitest). A `GATE_CMD` with one command that ran tests and another that ran none passes. Output without a known summary line passes, so this mode only catches the summaries it knows. Terminal colour codes and carriage returns are ignored.

For a real count, set `GATE_COUNT_RE` to a bash regex for the lines that report tests: group 1 is the count on that line, a match with an empty or no group 1 counts as one, and the counts are added up. `GATE_MIN_TESTS` is the fewest tests the run must report (default 1; a value above 1 needs `GATE_COUNT_RE`). `GATE_MIN_TESTS=0` turns the check off.

```
GATE_CMD="cargo test" GATE_COUNT_RE='^test result: ok\. ([0-9]+) passed' two-engines-gate
GATE_CMD="go test -v ./..." GATE_COUNT_RE='^--- PASS' two-engines-gate
```

go test and cargo test print a zero line for each package or target without tests even when others ran, so they have no built-in check and need `GATE_COUNT_RE`.

### A narrowed test command still passes

gate.sh records a pass when `GATE_CMD` exits 0 on a clean checkout and the test count check accepts its output. It does not know which tests the project has, so a command narrowed to fewer tests gets a pass when those tests pass. This reproduces with `node --test` (Node 20.19) in a scratch repository where `add()` returns the wrong result, with `test/add.test.js` for `add()` and `test/format.test.js` for another function. `GATE_CMD="node --test test/"` printed `gate: FAIL (exit 1)`. `GATE_CMD="node --test test/format.test.js"` printed `gate: PASS on <sha>` and wrote a pass record, because the one file it ran does not test `add()`. The zero-test check does not catch this, since one test ran. The `Command:` line in the pass record shows what was run, and merge-check.sh does not compare it with anything.

Two measures reduce the risk. The first is to set `GATE_COUNT_RE` and set `GATE_MIN_TESTS` to the number of tests the project has. gate.sh then refuses a run whose output reports fewer tests than that. In the scratch repository this refuses the one-file command with `the output reports 1 tests, fewer than GATE_MIN_TESTS=2`. You have to raise the number when you add tests, and the check compares the total the output reports, so it does not show which tests ran:

```
GATE_CMD="node --test test/" GATE_COUNT_RE='^# pass ([0-9]+)$' GATE_MIN_TESTS=2 two-engines-gate
```

The second is the other engine's review of the diff. `review-prompt.md` asks it to check anything that weakens an existing check, which includes a test script narrowed in a commit. A narrowed `GATE_CMD` typed on the command line is not in the diff, so only the count check applies to it. A review is a model's reading of the diff and can miss things.

## What it does not do

- It does not make the code correct. A review can miss things, and tests only check what they test.
- It is a local guard against merging the wrong commit, not a security boundary: anything with write access to the repository can write files under `.ai/`.
- It does not push, merge or talk to GitHub. merge-check.sh only answers yes or no.

## Files

- `bin/review.sh`, `bin/gate.sh`, `bin/merge-check.sh`: the gate.
- `review-prompt.md`: the reviewer instructions; edit it to add project rules.
- `demo.sh` and `examples/stand-in-reviewer.sh`: the offline demo.
- `examples/sample-verdict.md` and `examples/sample-verdict-claude-code.md`: verdicts from real reviews of the demo's first commit, one in each direction (Codex reviewing, then Claude Code reviewing).
- `examples/local-check.sh`: a minimal `GATE_CMD` example.
- `snippets/CLAUDE.md`, `snippets/AGENTS.md`, `docs/engines.md`: the parts specific to Claude Code and Codex.
- `install.sh`, `uninstall.sh`, `tests/run.sh`.
- `skills/two-engines-gate/SKILL.md`: the steps above as an Agent Skill for Claude Code and Codex.
- `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`: the Claude Code plugin and its marketplace.
- `.agents/plugins/marketplace.json`: the marketplace for Codex.
- `plugin.json`, `.codex-plugin/plugin.json` and `assets/icon.svg`: the portable plugin manifest and the Codex plugin manifest with its icon.
- `SECURITY.md`: how to report a security problem.

## Tests

`bash tests/run.sh` runs offline with the stand-in reviewer: syntax checks, a content scan of the tracked files, the demo in both directions, every review.sh exit code, gate.sh and merge-check.sh refusals, all three scripts refusing files flagged skip-worktree or assume-unchanged (with spaces, quotes, line breaks and control characters in the file names), and install and uninstall on scratch HOME folders with a byte-for-byte comparison. The repository gates itself with `GATE_CMD="bash examples/local-check.sh" GATE_COUNT_RE='^passed ([0-9]+), failed'`.

## Licence and the full kit

MIT, see `LICENSE`. Issues are welcome; there is no promised response time.

This repository is the free review and merge gate from the Two Engines Kit, described at https://rayastats.com/en/two-engines-kit.
