# Claude Code and Codex specifics

review.sh calls the engine that did not write the code. `BUILDER=claude` (the default) makes Codex the reviewer; `BUILDER=codex` makes Claude Code the reviewer. Both CLIs use their normal login; review.sh never reads or passes keys. Both get the same prompt: `review-prompt.md`, then the commits and the full diff from the base to HEAD.

## Codex as the reviewer

The call is:

```
codex exec -s read-only --color never --output-last-message <file> -
```

- `-s read-only` is the read-only sandbox: Codex can read files and run read-only commands such as `git diff`, but cannot write.
- The verdict is read only from the final message that `--output-last-message` saves, never from the log.
- `REVIEW_MODEL` adds `--model <name>`. Without it, Codex uses the model and reasoning effort set in `~/.codex/config.toml` (`model` and `model_reasoning_effort`).
- MCP servers configured in `~/.codex/config.toml` also start for the review. A server that can change things outside the sandbox works against a read-only review; set `enabled = false` on that server's `[mcp_servers.<name>]` table while reviewing.
- Hooks set up for Codex also run under `codex exec`. A Stop hook that asks Codex to continue after its review can replace the final message with an empty one; review.sh then finds no verdict and exits 1 without saving anything. Switch such a hook off for reviews, or add a line to `review-prompt.md` asking Codex to repeat its complete review if anything asks it to continue.
- Codex reads `AGENTS.md` files in the repository during the review. `snippets/AGENTS.md` is a short section to paste into the project's `AGENTS.md`. Codex stops adding instruction files once their combined size reaches `project_doc_max_bytes` (32 KiB by default), so keep the section short.

## Claude Code as the reviewer

The call is:

```
claude -p "Do the review described on standard input." --restricted --strict-mcp-config \
  --permission-mode dontAsk --tools "Read,Grep,Glob" --allowedTools "Read,Grep,Glob" \
  --disallowedTools "Bash,Edit,MultiEdit,Write,NotebookEdit,WebFetch,WebSearch,Task,Agent"
```

- Read, Grep and Glob are the only tools, so Claude Code cannot run commands, git included, and cannot edit or write files. That is why review.sh puts the commits and the diff into the prompt.
- `--strict-mcp-config` with no MCP configuration given means no MCP servers load.
- review.sh refuses to start when `claude --help` does not list `--restricted`; update Claude Code in that case.
- `REVIEW_MODEL` adds `--model <name>`; otherwise Claude Code uses its own default.
- `snippets/CLAUDE.md` is the matching section for the project's `CLAUDE.md`.

## The builder side

The builder is whichever engine writes the code in its normal interactive session. The snippets tell it to commit each change, stop, leave `.ai/` alone and never merge. review.sh, gate.sh and merge-check.sh are run by a person, or by the builder as plain commands, between commits.
