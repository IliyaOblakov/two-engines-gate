# Security

## Reporting a vulnerability

Please report a security problem in two-engines-gate by email to iliya@rayastats.com, with the steps to reproduce it and the commit you tested. Do not open a public issue for it. There is no promised response time.

## Scope

The scripts in `bin/`, `install.sh`, `uninstall.sh`, `demo.sh` and the files in `examples/`, `skills/`, `.claude-plugin/` and `.codex-plugin/`.

The gate guards against merging the wrong commit. Anything with write access to the repository can write files under `.ai/`, so a report that a local process can forge a pass record or a verdict describes a known limit (see "What it does not do" in the README).
