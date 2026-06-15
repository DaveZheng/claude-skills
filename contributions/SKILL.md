---
name: contributions
description: Summarize all my git contributions (commits, merges, PRs) grouped by feature/bug/addition with business context and links
---

You are summarizing the user's git contributions for a given time period. The output is a clean, scannable report suitable for standups, weekly updates, or manager check-ins.

## Usage

```
/contributions                  → today's contributions (workday)
/contributions yesterday        → yesterday
/contributions last week        → last 7 days
/contributions this week        → Monday through today
/contributions march 15-20      → specific date range
/contributions last 2 weeks     → last 14 days
/contributions this month       → first of month through today
/contributions Q1               → Jan 1 through Mar 31
```

If no argument is provided, default to **today** (the current workday).

## Step 1: Resolve date range

The user's timezone is **US Eastern (America/New_York)**.

Parse the argument as a natural-language date expression and convert to two absolute dates: `SINCE` and `UNTIL` (YYYY-MM-DD format). Use today's date from the system context.

Examples:
- "yesterday" → previous calendar day
- "last week" → 7 days ago through yesterday
- "this week" → most recent Monday through today
- "march 15-20" → March 15 through March 20 (of current year unless specified)
- "last 2 weeks" → 14 days ago through today
- No argument → today only (`SINCE` = today, `UNTIL` = tomorrow)

For "today" default, set `SINCE` to today's date and `UNTIL` to tomorrow so git captures the full day.

## Step 2: Gather contributions

Run these commands to collect all contributions by the user:

```bash
# Derive the GitHub repo URL for commit links
REPO_URL=$(git remote get-url origin | sed 's/git@github.com:/https:\/\/github.com\//' | sed 's/\.git$//')

# All commits authored by David in the date range (including merge commits)
git log --author="dwzheng17@gmail.com" --since="SINCE" --until="UNTIL" \
  --format="%H|%h|%s|%ai" --all

# Merged PRs in the date range
gh pr list --author="@me" --state=merged \
  --search="merged:SINCE..UNTIL" \
  --json number,title,mergedAt,url,headRefName,body \
  --limit 100
```

Use `$REPO_URL` when constructing commit links (e.g. `$REPO_URL/commit/abc1234`). PR links come from `gh` output directly.

Also check for PRs that were opened (but not yet merged) in the range:

```bash
gh pr list --author="@me" --state=open \
  --search="created:SINCE..UNTIL" \
  --json number,title,createdAt,url,headRefName,body \
  --limit 50
```

And PRs that were reviewed/approved:

```bash
gh pr list --state=all \
  --search="reviewed-by:@me merged:SINCE..UNTIL" \
  --json number,title,url,author \
  --limit 50
```

## Step 3: Group by feature / initiative

Analyze all collected commits and PRs. Group them into logical units — each representing a single feature, bug fix, improvement, or initiative. Signals for grouping:

- **Same PR** → always one group
- **Same branch name** → likely one group
- **Related commit messages** (e.g., "add migration for X" + "add API route for X" + "add frontend for X") → one group
- **Conventional commit prefix** (feat, fix, perf, docs, refactor, chore) → informs the category label

Assign each group a category label:
- **Feature** — new user-facing functionality
- **Fix** — bug fix or correction
- **Improvement** — performance, refactoring, DX enhancement
- **Infra** — CI/CD, test infrastructure, build tooling, deps
- **Docs** — documentation

## Step 4: Format output

Print the report in this exact format:

### Header

```
## Contributions: {date range description}
_{SINCE} — {UNTIL}_ (or just the single date if one day)
```

### Body

For each group, one entry:

```
- **{Business/product title}** — {Technical change description} [{PR link or commit link}]
```

Rules for the entry format:
- **Bold title** = the business or product goal, or the bug/problem being fixed. Written in plain language, not commit-message style. e.g., "Users couldn't see memory descriptions in settings" not "fix: show memory description instead of internal name"
- **After the dash** = the technical change. Brief, specific. e.g., "Updated memory settings to display the human-readable `description` field instead of the internal `name`"
- **Links** = PR link preferred (`[#965](url)`). If no PR, use short commit hash linked to GitHub (`[abc1234](url)`)
- If a group has multiple PRs, list them all: `[#960](url), [#965](url)`
- If a group has commits not tied to any PR, list the commit links separately

Sort groups within each category by most impactful/largest first.

Organize the output by category, with categories ordered: Features → Fixes → Improvements → Infra → Docs. Omit empty categories.

### PRs Opened (not yet merged)

If there are open PRs from the range, add a separate section:

```
### In Progress
- **{Title}** — {branch name} [{PR link}]
```

### PRs Reviewed

If the user reviewed PRs by others, add:

```
### Reviews
- {PR title} by {author} [{PR link}]
```

### Footer

End with a one-line summary count:

```
_{N features, N fixes, N improvements — N PRs merged, N commits}_
```

## Example output

```
## Contributions: Today
_2026-04-01_

### Features
- **Workspace-level access control for team collaboration** — Implemented full RBAC system with role-based permissions, workspace member management, and authorization middleware [#960](https://github.com/SmokeStudio/smoke-screen/pull/960)
- **AI-powered end-to-end testing** — Built E2E testing skill that analyzes code changes, runs Playwright browser tests, and reports results to Slack [#972](https://github.com/SmokeStudio/smoke-screen/pull/972)

### Fixes
- **Memory settings showed internal names instead of descriptions** — Updated settings display to use the human-readable `description` field [#965](https://github.com/SmokeStudio/smoke-screen/pull/965)

### Improvements
- **Approval tool responses were bloating token usage** — Slimmed down `listApprovals` response payload to reduce context window consumption [#895](https://github.com/SmokeStudio/smoke-screen/pull/895)

_2 features, 1 fix, 1 improvement — 4 PRs merged, 12 commits_
```

## Key principles

- **Business framing first.** The bold title should make sense to a PM or manager — what user problem was solved or what capability was added.
- **Technical precision second.** The description after the dash is for engineers — what actually changed.
- **Group aggressively.** 5 commits for one feature = 1 entry, not 5. The user wants a summary, not a git log.
- **Links are non-negotiable.** Every entry must have at least one clickable reference.
- **Don't pad.** If there's only 1 contribution, show 1 entry. Don't invent categories or filler.
