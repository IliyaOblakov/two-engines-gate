# two-engines-gate

A local review and merge gate for Claude Code and Codex. One engine writes the code; the other reviews the commit read-only and its verdict is saved under the exact commit it reviewed. The project's tests run on that same commit. `merge-check.sh` refuses unless HEAD has both a test pass and an ACCEPT.

Requirements: bash 4 or newer and git. Real reviews also need the Claude Code and Codex CLIs, installed and logged in. The demo and the tests need neither CLI, no account and no network. Tested on Linux (Ubuntu 24.04 under WSL2); `tests/run.sh` also needs GNU find and grep.

Built on information gathered since the first Codex and Claude CLIs.

## Try it in a minute

```
git clone https://github.com/IliyaOblakov/two-engines-gate.git
cd two-engines-gate
bash demo.sh
BUILDER=codex bash demo.sh
```

The demo builds a throwaway repository in a temporary folder and walks through one change: a commit with a bug the tests miss, the merge check refusing, a CHANGES REQUIRED review, a fix commit whose old evidence no longer counts, then tests and an ACCEPT on the new commit and the merge. A stand-in answers as the reviewer, so no model is called. `DEMO_REAL=1 bash demo.sh` calls the real reviewer CLI instead. The folder is removed at the end (`KEEP=1` keeps it).

## How it works

| Script | What it does | Writes |
|---|---|---|
| `bin/review.sh` | Sends the commits and the diff to the engine that did not write them, read-only. Takes the verdict from its final message only. | `.ai/reviews/<sha12>.md` |
| `bin/gate.sh` | Runs `GATE_CMD` on a clean checkout. Records a pass only when the command passed and left the checkout unchanged. | `.ai/tests/<sha>.pass` |
| `bin/merge-check.sh` | Refuses unless the checkout is clean and HEAD has a pass record and an ACCEPT from a reviewer that is not the builder. Never merges. | nothing |

Why the verdict is named after the commit: an ACCEPT for an older commit can quietly cover code nobody reviewed. A new commit needs a new review and a new test run. review.sh and gate.sh remove their earlier evidence for the commit before anything else, so a failed or refused run never leaves an old pass or ACCEPT behind.

Exit codes of review.sh: 0 for `Verdict: ACCEPT`, 2 for `Verdict: CHANGES REQUIRED`, 1 when there is no verdict (the reviewer failed, the final message held no single verdict line, the checkout changed during the review, or a setting was wrong).

## Install

From a clone, run `bash install.sh`. It copies the scripts and the review prompt to `~/.local/share/two-engines-gate` and adds `two-engines-review`, `two-engines-gate` and `two-engines-merge-check` to `~/.local/bin` (`PREFIX` changes `~/.local`). It stops without changing anything when one of those files already exists. `bash uninstall.sh` removes exactly what the install created; a file edited after the install, or a folder that also holds other files, is kept and reported, and running it again after dealing with those finishes the job.

No install is needed to use it: every script runs from the clone, for example `path/to/two-engines-gate/bin/review.sh`.

Add `.ai/` to the project's `.gitignore`. The scripts ignore changes under `.ai/` when they check for a clean checkout.

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

## Tests

`bash tests/run.sh` runs offline with the stand-in reviewer: syntax checks, a content scan of the tracked files, the demo in both directions, every review.sh exit code, gate.sh and merge-check.sh refusals, and install and uninstall on scratch HOME folders with a byte-for-byte comparison. The repository gates itself with `GATE_CMD="bash examples/local-check.sh"`.

## Licence and the full kit

MIT, see `LICENSE`. Issues are welcome; there is no promised response time.

This repository is the free review and merge gate from the Two Engines Kit, described at https://rayastats.com/en/two-engines-kit.
