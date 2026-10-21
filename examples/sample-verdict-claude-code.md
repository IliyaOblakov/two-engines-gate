<!-- A real review by Claude Code, run with BUILDER=codex, saved by bin/review.sh unchanged except that the temporary folder path was removed from file links. The reviewed commit is the first commit of demo.sh (sum.sh skips its first argument; the test misses it), built in a throwaway repository on 2026-10-21, so the hashes differ from a fresh demo run. Claude Code 2.1.304 with its default model. The review prompt was review-prompt.md plus one line asking the reviewer to repeat its review if a local hook asked it to continue. Correction, not part of the review: in the third finding, the script as shown prints 0 for `bash sum.sh 1 abc`, not 1, because it also skips the first argument; the point about unvalidated input stands. -->

Head: 9936f6528e57105ff7309a67aad58d1f482f94ed
Base: a0f523a0689f742a322c0123536d4060b94c2562 (main)
Builder: codex
Reviewer: claude
Date: 2026-10-21 14:17 EEST

The README gives no spec, so the script's name and the test are the only statements of intent. Both say `sum.sh` should add its arguments.

**Review of `feat: add sum.sh`**

The script silently drops the first argument. `"${@:2}"` on `sum.sh:3` slices the positional parameters starting at the second one, so whatever is passed first is never added. The test on `test.sh:1` only runs `sum.sh 0 4`, where the dropped argument is zero, so the result happens to equal the correct answer and the bug is invisible. The test would pass on a script that printed the sum of every argument except the first, and it would pass on one that summed all of them, so it does not distinguish correct from broken behaviour.

There is also no input validation. A non-numeric argument reaches bash arithmetic directly, which treats a bare word as a variable name and evaluates it to zero rather than failing. The script returns a wrong total with exit status zero instead of an error.

Verdict: CHANGES REQUIRED

- **blocker, `sum.sh:3`**: The loop iterates `"${@:2}"`, which skips the first argument. Running `bash sum.sh 1 2 3` prints `5` instead of `6`. Running `bash sum.sh 7` prints `0`. The script named `sum` does not sum its inputs. Change the slice to iterate over all positional parameters.

- **should-fix, `test.sh:1`**: The only test case uses `0` as the first argument, so dropping that argument produces the correct answer by coincidence. The test passes on the buggy code in this diff. Add at least one case with a non-zero first argument, for example `sum.sh 1 2 3` expecting `6`, and a single-argument case such as `sum.sh 5` expecting `5`.

- **should-fix, `sum.sh:3`**: Non-numeric input is not rejected. `bash sum.sh 1 abc` prints `1` and exits zero, because `abc` is treated as an unset variable in `$((...))`. An argument like `x[0]` or an arithmetic expression such as `2+2` is also evaluated rather than rejected. Validate that each argument is an integer and exit non-zero with a message otherwise.

- **nit, `sum.sh:1`**: The file is executed as `bash sum.sh` from the test, which works, but the diff does not mark the file executable despite the shebang. Either add the executable bit or drop the shebang to avoid implying direct invocation works.

- **nit, `test.sh:1`**: `test.sh` has no shebang and uses a relative path to `sum.sh`, so it only works when run from the repository root with a POSIX shell. Running it from another directory fails with "No such file or directory" rather than a clear test failure. Resolve the script's own directory or document the required working directory.
