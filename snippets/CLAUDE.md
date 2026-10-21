## Review gate

This project uses two-engines-gate: every commit is reviewed read-only by the other engine and tested before it may merge.

When writing code:
- Finish one change, commit it with the project's git identity and a plain commit message, then stop and report the commit.
- Treat a CHANGES REQUIRED verdict as the fix list: fix every finding in a new commit. Do not amend, rebase or squash a reviewed commit.
- Never create, edit or delete anything under `.ai/`. Verdicts and test pass records come only from review.sh and gate.sh.
- Never merge or push. A person merges after merge-check.sh passes.

When asked to review a change for the gate:
- Stay read-only: change no files and commit nothing.
- Follow the review prompt and end with exactly one `Verdict:` line.
