<!-- A real review by Codex, run with BUILDER=claude, saved by bin/review.sh unchanged except that the temporary folder path was removed from file links. The reviewed commit is the first commit of demo.sh (sum.sh skips its first argument; the test misses it), built in a throwaway repository on 2026-10-21, so the hashes differ from a fresh demo run. codex-cli 0.163.0 with its configured default model. The review prompt was review-prompt.md plus one line asking the reviewer to repeat its review if a local hook asked it to continue. -->

Head: cc77c327061d96b838ad0a52ceca6d69cc73c441
Base: c6ee6255f8f5b094855f4bb189e7cd4da671832a (main)
Builder: claude
Reviewer: codex
Date: 2026-10-21 14:16 EEST

Static review found one functional defect; no tests or builds were run.

Verdict: CHANGES REQUIRED

- **should-fix**: [sum.sh:3](sum.sh:3) skips the first operand because `${@:2}` starts at argument 2. `bash sum.sh 3 4` prints `4` instead of `7`; `bash sum.sh 5` prints `0` instead of `5`. Include every supplied operand. The sole check at [test.sh:1](test.sh:1) masks this defect by using `0` as the first operand. Add coverage with a nonzero first operand and a single operand.
