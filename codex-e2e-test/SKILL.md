---
name: codex-e2e-test
description: Run the adversarial, phased E2E flow on OpenAI Codex instead of Claude — deterministic golden baseline first, then codex-exec explorers → planner → one browser executor (Playwright MCP) → skeptic verification → golden-suite curator, reporting to Slack with screenshots. Mirrors the Claude /e2e-test workflow's architecture; all test reasoning and browser-driving run on OpenAI credits, Claude only prechecks, launches, and triages. Supports pr-<n> / <url> / golden / --local / --dm / --single.
argument-hint: "[pr-<n> | <url> | golden [target]] [--local | --dm] [--single] [-e effort] [-m model]"
---

You are launching a **phased adversarial E2E run that executes on OpenAI Codex, not Claude**. The orchestrator (`~/.codex/tools/e2e-orchestrator.mjs`) mirrors the Claude `/e2e-test` Workflow architecture one phase at a time: golden baseline (deterministic, no LLM) → parallel explorer `codex exec`s (diff→frontend trace + fragility hunting) → a planner exec that designs a scenario matrix with a mandatory break-it quota → ONE browser executor exec driving Playwright MCP → parallel skeptic execs that re-judge every verdict → a curator exec that heals/promotes the deterministic specs in `e2e/golden-paths/`. Your job: precheck, launch, triage. Keep your own token use minimal — the point is divesting E2E spend from Anthropic.

Why phased (vs the old single exec): one process that designs, executes, and grades its own scenarios converges on all-green. Separating the planner (who must attack), the executor (who only observes), and the skeptics (who must overturn) is what makes failures findable. The browser phase stays a single process — one login, one session, one Slack thread cannot split — but no reasoning about *what to test* or *whether it passed* lives there anymore.

Non-LLM alternative, considered and bounded: the deterministic golden suite (`e2e/golden-paths/`, zero tokens) is the non-LLM layer and always runs first; these LLM phases exist only for what static specs cannot assert — behavior new in this diff, break attempts against it, and model-lane checks. Anything repeatable the run discovers gets promoted INTO the deterministic layer by the curator, shrinking future LLM work.

## Files

- `e2e-orchestrator.mjs` (this dir; runtime symlink `~/.codex/tools/e2e-orchestrator.mjs`) — the phased orchestrator. Run `--help` for flags.
- `codex-e2e-prompt.md` (this dir; runtime symlink `~/.codex/prompts/e2e-test.md`) — the legacy single-process methodology. Still used by the native `/e2e-test` slash command inside interactive Codex, and by `--single` mode here. Its scenario-design step carries the same adversarial mandate as the orchestrator's planner.

Both reuse the repo's assets verbatim (`e2e/slack_helper.py`, `e2e/.env`, `e2e/golden-paths/`, `e2e/golden-paths/support/match-specs.mjs`); nothing is reimplemented.

## Install (fresh machine)

```sh
mkdir -p ~/.codex/prompts ~/.codex/tools
ln -sf "$HOME/.claude/skills/codex-e2e-test/codex-e2e-prompt.md" ~/.codex/prompts/e2e-test.md
ln -sf "$HOME/.claude/skills/codex-e2e-test/e2e-orchestrator.mjs" ~/.codex/tools/e2e-orchestrator.mjs
```

Requires `codex` CLI logged in (`codex login`), node/`npx` (Playwright MCP is injected per-run via `-c`; nothing is written to `~/.codex/config.toml`), `gh`, `python3`, and `e2e/.env` with creds.

## Step 1 — Precheck

```sh
command -v codex >/dev/null || { echo "codex CLI not installed"; exit 1; }
test -e ~/.codex/tools/e2e-orchestrator.mjs || { echo "orchestrator missing — run Install"; exit 1; }
test -f e2e/.env || { echo "e2e/.env missing"; exit 1; }
grep -q E2E_USER_EMAIL e2e/.env && grep -q E2E_USER_PASSWORD e2e/.env || { echo "creds not set"; exit 1; }
test -d e2e/node_modules || (cd e2e && npm install)
```

Run from the repo/worktree under test. Codex auth errors → tell the user to run `codex login` (interactive; you can't) and stop. **Never echo credential values.**

## Step 2 — Resolve mode

Target grammar is handled by the orchestrator itself (`pr-<n>` / bare number / URL / none → localhost:3000). You resolve only:

- `golden` as first token → **golden mode is deterministic** (`cd e2e && E2E_BASE_URL=<target> npx playwright test`, no LLM) — there is nothing to divest. Tell the user the native `/e2e-test golden` runs it for free; only proceed on Codex if they insist (then just run the deterministic suite and triage — no orchestrator).
- `--single` → legacy single-process mode: assemble and launch the old `codex exec` with `codex-e2e-prompt.md` + RUN CONTEXT (exact recipe in "Appendix — `--single` launch" below). Use only when explicitly requested or the orchestrator is broken.
- `--dry-run` → pass through; the orchestrator prints its resolved plan and call count, spending nothing. **Offer this first if the user hasn't run this before.**
- Cost flags to surface: `-e low|medium|high|xhigh` (default medium; planner/curator run one notch higher), `-m <model>` (default gpt-5.5 — minis fumble long multi-tool browser sessions), `--fast-model <m>` (cheaper model for explorers + skeptics only), `-j <n>` concurrency.
- Curation is auto-gated: the curator writes spec files only when the checked-out branch IS the PR's head branch; otherwise it proposes candidates. `--curate` / `--no-curate` override.

## Step 3 — Launch (background)

```sh
RUN_LOG="/tmp/codex-e2e/launch-$(date +%Y%m%d-%H%M%S).log"
mkdir -p /tmp/codex-e2e
node ~/.codex/tools/e2e-orchestrator.mjs <target-from-step-2> <reporting-and-cost-flags> > "$RUN_LOG" 2>&1
# e.g.: node ~/.codex/tools/e2e-orchestrator.mjs pr-965 --dm -e medium
```

Pass exactly the target and flags you resolved in Step 2 — never copy the example values.

Run with the Bash tool's `run_in_background: true` — a full run (explorers + browser session + skeptics + curator) routinely exceeds the foreground cap. The orchestrator streams phase progress to stderr (captured in the log), posts live scenario results + verified corrections to Slack itself, and prints a final JSON report to stdout (also saved to `/tmp/codex-e2e/<ts>/report.json`).

Notes that are load-bearing (do not "fix" them):
- The browser executor runs `--dangerously-bypass-approvals-and-sandbox` — without it Codex auto-cancels external MCP tool calls and then hallucinates page contents. User's own machine + trusted repo only; never point at untrusted code or a malicious URL.
- Playwright MCP is injected with `--isolated` (fresh in-memory profile) so it can't collide with a concurrent Claude browser session or a leftover profile lock.
- Explorers/planner/skeptics run `-s read-only` — they can read the repo and screenshots but cannot write or execute; only the executor and curator are unsandboxed.

## Step 4 — Triage and report back

Parse the final JSON from the log/report.json — do not dump it raw:

1. **Verified counts first** (`counts`), then the break-attempts line (`breaksLine`) — a zero-❌ run must still show what was attempted and survived; if `attemptedBreaksNote` is thin, say the run was soft rather than calling it green.
2. **Spot-check every ❌** against the actual code/diff before presenting it as fact (Codex can hallucinate); flag unconfirmed ones as "unverified".
3. **Skeptic overturns** — report each (both directions) with its one-line reasoning; they're posted in the Slack thread too.
4. **Golden layer** — baseline pass/fail, healed/promoted/demoted specs (files land uncommitted on the branch), `regressionsSuspected` verbatim, `candidates` when the curator ran in proposal-only mode (foreign PR or `--no-curate`).
5. **Slack thread** (unless `--local`) — `report.json` carries `slackThread: {channel, thread_ts}`; name the channel (or DM) and confirm the thread with live results + screenshots exists. Add a cost note (model/effort used, so the user can tune).

If the run died early (target unreachable, login failed, codex auth), the log's last stderr lines say where — report that with evidence and stop.

## Appendix — `--single` launch (legacy single-process mode)

One `codex exec` does everything (the pre-orchestrator architecture; weaker — it plans and grades its own work). Build the combined prompt (methodology + resolved RUN CONTEXT), launch in the background, triage the log:

```sh
REPO="$(pwd)"
# Outside the repo on purpose: run.log captures Codex's stdout, which includes the
# login step — keep it off the working tree so creds can't be committed.
RUN_DIR="/tmp/codex-e2e/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$RUN_DIR"
{
  cat ~/.codex/prompts/e2e-test.md
  cat <<CTX

## RUN CONTEXT (resolved by the launcher — authoritative; ignore the \$ARGUMENTS line above)
- Raw argument: <the user's raw arg, or "(none)">
- Target URL: <resolved url>
- Mode: <normal | golden>
- Reporting: <slack:#e2e-reporting | slack:dm | local>
- Repo root: $REPO
Proceed with the methodology above against this target.
CTX
} > "$RUN_DIR/prompt.md"

codex exec \
  -C "$REPO" \
  -c 'mcp_servers.playwright.command="npx"' \
  -c 'mcp_servers.playwright.args=["-y","@playwright/mcp@latest","--headless","--isolated","--viewport-size","1280x720","--output-dir","/tmp/e2e-recordings"]' \
  -c 'mcp_servers.playwright.startup_timeout_sec=180' \
  -c 'model_reasoning_effort="<effort from -e, default medium>"' \
  -m "<model from -m, default gpt-5.5>" \
  --dangerously-bypass-approvals-and-sandbox \
  --skip-git-repo-check \
  - < "$RUN_DIR/prompt.md" > "$RUN_DIR/run.log" 2>&1
```

The user's `-e`/`-m` flags map to `model_reasoning_effort` and `-m` here — substitute them, don't ship the defaults blindly. Every other flag is load-bearing (same reasons as the orchestrator's executor phase): `--dangerously-bypass-approvals-and-sandbox` or Codex auto-cancels the MCP tool calls and hallucinates page contents; `- < prompt.md` feeds stdin and EOFs cleanly; `--isolated` avoids the persistent-profile lock. Precheck first: `test -e ~/.codex/prompts/e2e-test.md || { echo "prompt missing — run Install"; exit 1; }` (the orchestrator path doesn't need that file, so Step 1 doesn't check it).
