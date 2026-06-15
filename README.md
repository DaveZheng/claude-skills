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
| `contributions` | Summarize my git contributions grouped by feature/bug/addition with business context. |
| `sync-perms` | Sync whitelisted permissions from the current worktree back to the main checkout. |

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
