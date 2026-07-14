---
name: codex-agent
description: Dispatch one subagent-equivalent unit of work to OpenAI Codex (`codex exec`) instead of a Claude subagent, to conserve Anthropic quota near the usage cap. Triggered when codex-mode is armed (the PreToolUse hook denies the Task/Agent tool). Runs read or write (agentic edits) in the working dir; the caller MUST verify the result with git diff.
---

# codex-agent — run work on Codex, not Claude

Use this when **codex-mode is armed** (`~/.claude/codex-mode` exists). In that state the PreToolUse hook denies the `Task`/`Agent` tool on purpose: spawning a Claude subagent burns the Anthropic quota you're near the cap on. Route the same work to Codex (OpenAI credits) instead.

## Run it

Pipe the task to the worker on stdin — give it exactly what you'd have given the Claude subagent, but be explicit: `codex exec` is less steerable mid-run, so scope the task and name the files it may touch.

```sh
~/.claude/skills/codex-agent/codex-agent.sh --cd "$REPO" <<'EOF'
<full task here>
EOF
```

Flags:
- `--cd DIR` — working root (default: cwd). For parallel independent edits, give each worker its own `git worktree` dir so they can't collide.
- `--tier default|fast|deep|mini` — overrides the tier. Default reads `~/.claude/codex-mode` contents (`cwdcf` writes `fast` = OpenAI priority tier: ~1.5x faster, ~2.5x $). Table: `~/.claude/codex-tiers.sh`.
- `--read-only` — pure search/exploration, no writes.
- `--full-access` — only if the task must run builds/tests that write outside WORKDIR (uses `--dangerously-bypass-approvals-and-sandbox`). Default is confined `workspace-write`.

## Verify — do not trust the output

Codex edits in place. After it returns, **read `git diff` and confirm the change** before continuing. That verification (cheap input tokens) is the entire point: the expensive model only checks, it doesn't regenerate. If the edit is wrong, re-dispatch with a tighter prompt or fix it inline.

## One change vs fan-out

A single `codex exec` edits many files itself — for one coherent multi-file change, ONE worker is enough. Only fan out (N workers on N `git worktree`s, bounded concurrency) when the tasks are genuinely independent.

## Exit codex-mode

`rm ~/.claude/codex-mode` (or the `cwoff` alias) once you're past the cap.
