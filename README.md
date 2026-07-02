# claude-skills

My personal, user-level [Claude Code](https://code.claude.com) skills. This directory **is**
`~/.claude/skills/`, so anything committed here is live in Claude Code on this machine and
syncs across machines via git.

Each skill is a folder with a `SKILL.md` (YAML frontmatter `name` + `description`, then the
instructions body). Claude loads them automatically; invoke with `/<skill-name>`.

## Skills

| Skill | What it does |
|-------|--------------|
| `confer-with-codex` | Get a second opinion from OpenAI Codex (`codex exec`, read-only) on the current approach, then triage its reply into pointers / conflicts / redesign. `--fast` / `--deep` / `--diff`. |
| `codex-adversarial-review` | Adversarial, multi-agent code review that runs on OpenAI Codex instead of Claude (find → verify → synthesize). Divests review spend from Anthropic; Claude only launches + triages. |
| `codex-e2e-test` | Dynamic AI E2E test flow run on OpenAI Codex instead of Claude — analyze diff → trace to frontend → drive Playwright MCP → report to Slack. The 1:1 Codex counterpart of `e2e-test`; divests E2E spend from Anthropic. |
| `contributions` | Summarize my git contributions grouped by feature/bug/addition with business context. |
| `sync-perms` | Sync whitelisted permissions from the current worktree back to the main checkout. |

The `codex-*` skills run their heavy work inside `codex exec` (OpenAI credits) and install a
companion prompt into `~/.codex/prompts/` (a symlink back into this repo, so it doubles as a
native Codex slash-command). Each skill's `SKILL.md` has an **Install** step with the exact
`ln -sf` commands; run it once per machine after syncing this repo.

## Set up on a new machine

```sh
# If ~/.claude/skills does NOT exist yet:
git clone git@github.com:DaveZheng/claude-skills.git ~/.claude/skills

# If ~/.claude/skills already exists (e.g. plugins put skills there):
cd ~/.claude/skills
git init
git remote add origin git@github.com:DaveZheng/claude-skills.git
git fetch
git checkout -t origin/main      # add -f if it complains about an existing untracked file
```

Plugin-managed skills (e.g. `nia`, a symlink into `~/.crust`) are gitignored — their own
installers recreate them per machine.

## Day-to-day

```sh
cd ~/.claude/skills
git add <skill> && git commit -m "..." && git push   # share a new/updated skill
git pull                                              # pull updates on another machine
```

New skills you author here are tracked automatically (no `.gitignore` edit needed).
