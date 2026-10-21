#!/usr/bin/env bash
# A minimal test command for gate.sh: GATE_CMD="bash examples/local-check.sh".
# It checks the syntax of every tracked shell script and then runs the repository's own tests.
# Replace the last line with the project's real test command, for example "npm test" or "pytest".
set -euo pipefail
git ls-files -z '*.sh' | xargs -0 -r -n 1 bash -n
bash tests/run.sh
