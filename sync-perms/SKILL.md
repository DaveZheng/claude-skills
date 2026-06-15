---
name: sync-perms
description: Sync whitelisted permissions from current worktree back to the main project settings. Use when you've approved permissions in a worktree and want them to persist.
disable-model-invocation: true
allowed-tools: Read Write Bash Edit AskUserQuestion
---

# Sync Worktree Permissions

Merge any new permission rules from the current worktree's settings into the main project's `.claude/settings.local.json`.

## Detect paths

1. Get the main repo path:
   ```bash
   git worktree list --porcelain | head -1 | sed 's/^worktree //'
   ```
   This is the `MAIN_REPO` path. If the current directory IS the main repo (not a worktree), tell the user "You're not in a worktree — nothing to sync" and stop.

2. The worktree settings file is: `<current dir>/.claude/settings.local.json`
3. The main project settings file is: `<MAIN_REPO>/.claude/settings.local.json`

If the worktree settings file doesn't exist, tell the user there are no worktree-specific permissions to sync and stop.

## Compare permissions

1. Read both files and extract the `permissions.allow` arrays.
2. Find entries in the worktree list that are NOT already in the main list. These are the "new" permissions.
3. If there are no new permissions, tell the user everything is already in sync and stop.

## Consolidation pass

Before merging, check each new permission for consolidation opportunities:

- **Specific commands that match an existing wildcard**: If the main list already has `Bash(git:*)` and the worktree adds `Bash(git checkout main)`, skip it — it's already covered.
- **Multiple specific commands that should become a wildcard**: If there are 2+ new entries for the same command prefix (e.g., `Bash(npm install foo)` and `Bash(npm install bar)`), suggest consolidating to a wildcard (`Bash(npm install:*)`).
- **One-off commands vs broad rules**: For entries that look like one-time approvals (e.g., a specific file path, a specific echo command), ask the user: "This looks like a one-off — should I generalize it to a wildcard, add it as-is, or skip it?"

Present the proposed changes in a clear table:

```
| # | Worktree permission          | Action              |
|---|------------------------------|----------------------|
| 1 | Bash(npm install foo)        | Generalize → npm install:* |
| 2 | Bash(railway logs -s smoke)  | Already covered by railway:* |
| 3 | Bash(curl https://specific)  | Ask user             |
```

Ask the user to confirm the plan before writing anything. Accept responses like "looks good", "yes", or per-line overrides like "skip 3".

## Write changes

1. Read the main settings file again (in case it changed).
2. Add the confirmed new permissions to the `permissions.allow` array.
3. Write the updated file using the Write tool, preserving all other fields (not just permissions).
4. Show the user a summary of what was added.

## Rules

- NEVER remove existing permissions from the main file.
- NEVER modify the worktree settings file.
- If the main settings file doesn't exist yet, create it with just the new permissions.
- Preserve JSON formatting (2-space indent).
