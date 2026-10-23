---
name: two-engines-gate
description: Run the two-engines-gate checks on the checked-out commit of a git repository. gate.sh runs the project's tests and records a pass for that exact commit, review.sh asks the engine that did not write the commit (Codex when Claude Code wrote it, Claude Code when Codex wrote it) for a read-only review and saves the verdict under the commit, and merge-check.sh answers whether HEAD may merge. Use when a change is committed on a branch and needs a test run, a review by the other engine or a merge check before it goes to main.
license: MIT
compatibility: Needs bash 4 or newer and git. Real reviews need the Claude Code and Codex CLIs, installed and logged in. Tested on Linux. macOS is not tested and needs a newer bash than the bash 3.2 it ships.
---

# two-engines-gate

Three bash scripts from the two-engines-gate repository check one commit before it merges. Each script works on the checked-out commit of the repository it is run in.

| Script | Installed name | What it does | Writes |
|---|---|---|---|
| `bin/gate.sh` | `two-engines-gate` | Runs `GATE_CMD` on a clean checkout. Records a pass only when the command passed, left the checkout unchanged and did not report a run of zero tests. | `.ai/tests/<sha>.pass` |
| `bin/review.sh` | `two-engines-review` | Sends the commits and the diff to the engine that did not write them, read-only. Takes the verdict from its final message only. | `.ai/reviews/<sha12>.md` |
| `bin/merge-check.sh` | `two-engines-merge-check` | Refuses unless the checkout is clean and HEAD has a pass record and an ACCEPT from a reviewer that is not the builder. Never merges. | nothing |

## Find the scripts

- After `bash install.sh` in a clone of two-engines-gate, the installed names above are in `~/.local/bin`.
- Without an install, run each script by its path in the clone, for example `path/to/two-engines-gate/bin/review.sh`.
- When two-engines-gate is enabled as a Claude Code plugin, its `bin/` folder is on the Bash tool's PATH, so `gate.sh`, `review.sh` and `merge-check.sh` run by name.

The steps below use the installed names; with the other two ways, use the script path or name instead.

## Steps

Run every command from the root of the project's repository, after the change is committed on a branch. The project's `.gitignore` should list `.ai/`.

1. Run the tests on the commit. Replace `npm test` with the project's test command:

   ```
   GATE_CMD="npm test" two-engines-gate
   ```

   With `GATE_COUNT_RE` unset, gate.sh reads the summary lines of pytest, unittest, `node --test`, mocha, Jest and Vitest and refuses a run they report as zero tests. For other test runners, set `GATE_COUNT_RE` to a bash regex for the lines that report tests. The README of two-engines-gate has examples for go test and cargo test.

2. Ask the other engine for a review:

   ```
   BUILDER=claude two-engines-review
   ```

   `BUILDER` names the engine that wrote the commit. `claude` (the default) makes Codex the reviewer, and `codex` makes Claude Code the reviewer. Exit 0 means `Verdict: ACCEPT` and exit 2 means `Verdict: CHANGES REQUIRED`. Exit 1 means no verdict: the reviewer failed, its final message held no single verdict line, the checkout changed during the review, or a setting was wrong.

3. Check the commit:

   ```
   two-engines-merge-check
   ```

   Exit 0 means HEAD has a test pass and an ACCEPT. Exit 1 is a refusal, with the reason on stderr.

4. On CHANGES REQUIRED, fix every finding in a new commit and run steps 1 to 3 again on the new commit. A pass record and a verdict cover only the commit they were made for, so each new commit needs a new test run and a new review.

## Rules

- Never merge or push. A person merges after merge-check.sh passes.
- Never create, edit or delete anything under `.ai/`. Verdicts and test pass records come only from review.sh and gate.sh.
- Do not amend, rebase or squash a reviewed commit. Fix findings in a new commit.

## Settings

- `REVIEW_BASE` sets the start of the reviewed range (default `origin/main`, else `main`).
- `REVIEW_MODEL` picks the reviewer's model.
- `GATE_MIN_TESTS` is the fewest tests a run must report (default 1; a value above 1 needs `GATE_COUNT_RE`). `GATE_MIN_TESTS=0` turns the check off.

`docs/engines.md` in the two-engines-gate repository has the exact reviewer calls and what each engine can and cannot do.

## Limits

A review can miss things, and tests only check what they test. Anything with write access to the repository can write files under `.ai/`, so the gate guards against merging the wrong commit and gives no protection against a hostile process.

## Try it offline

`bash demo.sh` in a clone of two-engines-gate builds a throwaway repository and takes one change through a refused merge, a CHANGES REQUIRED review, a fix and a merge. It uses a stand-in reviewer and needs no network and no account.
