---
name: codex-e2e-test
description: Run the dynamic AI E2E test flow on OpenAI Codex instead of Claude — analyze the diff → trace to frontend → drive a real browser via Playwright MCP → report to Slack with screenshots, mirroring /e2e-test. All the test reasoning AND the browser-driving run inside a single `codex exec` (OpenAI credits); Claude only prechecks, launches, and triages the result, so Claude-token cost is minimal. Use to run E2E while divesting the spend from Anthropic. Supports pr-<n> / <url> / golden / --local / --dm.
argument-hint: "[pr-<n> | <url> | golden [target]] [--local | --dm] [-e effort] [-m model]"
---

You are launching a **dynamic E2E test run that executes on OpenAI Codex, not Claude**. The token-heavy work — reading the diff, tracing it to frontend surfaces, designing scenarios, and driving a real browser through Playwright MCP (snapshots, clicks, screenshots), plus posting live results to Slack — all happens inside ONE `codex exec` process. Your job is only to: precheck, resolve the target + flags, launch the process, then triage its final report for the user. Keep your own token use lean — the point of this skill is to move E2E spend off Anthropic, exactly as `codex-adversarial-review` does for code review.

This is the 1:1 Codex counterpart of the Claude `e2e-test` skill: **same methodology, same browser tool (Playwright MCP), same Slack reporting, same golden-path suite — only the execution engine changes.** It reuses the repo's existing assets verbatim (`e2e/slack_helper.py`, `e2e/.env`, `e2e/golden-paths/`); it does NOT reimplement them.

## Executor

`~/.codex/prompts/e2e-test.md` — the full E2E methodology (10 steps + golden paths + verdict discipline) written for a Codex agent. It is version-controlled here as `codex-e2e-prompt.md`; the runtime path is a symlink to it (single source of truth). You feed this prompt to `codex exec` with a **RUN CONTEXT** block appended (the resolved target + flags), and Codex runs the whole flow.

There is no orchestrator fan-out here (unlike `codex-adversarial-review`): an E2E run is one sequential browser session — one login, one Slack thread, shared state — so it cannot be split across parallel `codex exec` processes. One process does everything.

## Install (fresh machine)

The prompt is version-controlled here as `codex-e2e-prompt.md`; the runtime path `~/.codex/prompts/e2e-test.md` is a symlink to it, which also registers a native `/e2e-test` slash-command inside interactive Codex. On a machine that has synced this repo but not the symlink:

```sh
mkdir -p ~/.codex/prompts
ln -sf "$HOME/.claude/skills/codex-e2e-test/codex-e2e-prompt.md" ~/.codex/prompts/e2e-test.md
```

Requires the `codex` CLI logged in (`codex login`) and Node/`npx` available (Playwright MCP is `npx @playwright/mcp@latest`). Nothing is written to `~/.codex/config.toml` — the Playwright MCP server is injected per-run via `-c` overrides (see Step 3). The native `/e2e-test` slash-command needs Playwright MCP present in Codex to drive the browser; if you want to use it interactively, add the same `[mcp_servers.playwright]` block from Step 3 to `~/.codex/config.toml` permanently. The Claude-launched path below needs no such edit.

## Step 1 — Precheck

```sh
command -v codex >/dev/null || { echo "codex CLI not installed"; exit 1; }
test -L ~/.codex/prompts/e2e-test.md || test -f ~/.codex/prompts/e2e-test.md || { echo "prompt missing at ~/.codex/prompts/e2e-test.md — run the Install step"; exit 1; }
test -f e2e/.env || { echo "e2e/.env missing (E2E_USER_EMAIL / E2E_USER_PASSWORD)"; exit 1; }
grep -q E2E_USER_EMAIL e2e/.env && grep -q E2E_USER_PASSWORD e2e/.env || { echo "creds not set in e2e/.env"; exit 1; }
```

Run from the repo you want tested (the worktree/checkout). If a later run fails with a Codex auth error, tell the user to run `codex login` themselves (interactive — you can't) and stop. **Never echo the credential values** — only check that the keys exist.

## Step 2 — Resolve the target and flags

Map the user's argument to a target URL, using the **same grammar as `/e2e-test`**:

- no arg → `http://localhost:3000`
- `pr-<number>` or a bare number → `https://smoke-web-smoke-screen-pr-<number>.up.railway.app`
- a full URL → use as-is
- `golden` as the first token → **golden mode** (run ONLY the deterministic golden-path specs); the remaining token, if any, is the target resolved by the rules above

Reporting flags (pass through to the RUN CONTEXT):
- `--local` → print results to the run log only, no Slack
- `--dm` → post to the PR author's Slack DM instead of `#e2e-reporting`

Cost/rigor flags (surface these — the user is cost-conscious):
- `-e <effort>` low|medium|high|xhigh (default **medium** — good balance for long tool-driving sessions; xhigh is slow/expensive across dozens of browser turns)
- `-m <model>` finder model (default gpt-5.5 — the mini fumbles multi-tool browser sequences)
- `--dry-run` → resolve everything and print the exact `codex exec` command + planned target, spend nothing. **Offer this first if the user hasn't run this before.**

**Golden-only mode is deterministic** (`npx playwright test`, no LLM) — there is nothing to divest there. If the user asks for `golden` with no dynamic scenarios, tell them the native `/e2e-test golden` runs it just as well for free; only proceed on Codex if they explicitly want it there.

## Step 3 — Launch (background)

Build the combined prompt (methodology + resolved RUN CONTEXT), then launch `codex exec`. A full dynamic run (10+ scenarios in a real browser) routinely exceeds the 10-minute foreground Bash cap, so **launch it in the background** and let Codex post progress to Slack live; you wait for the process to exit, then triage the log.

```sh
REPO="$(pwd)"
# Outside the repo on purpose: run.log captures Codex's stdout, which includes the
# login step — keep it off the working tree so creds can't be committed.
RUN_DIR="/tmp/codex-e2e/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$RUN_DIR"
# Combined prompt = methodology + the run context you resolved in Step 2.
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
  -c 'model_reasoning_effort="medium"' \
  --dangerously-bypass-approvals-and-sandbox \
  --skip-git-repo-check \
  - < "$RUN_DIR/prompt.md" > "$RUN_DIR/run.log" 2>&1
```

Run this with the Bash tool's `run_in_background: true`. Notes on the flags — each is load-bearing, do not drop them:

- **`--dangerously-bypass-approvals-and-sandbox`** — REQUIRED. Without it, Codex auto-cancels the external Playwright MCP tool calls ("user cancelled MCP tool call") and then *hallucinates* the page contents. It also lets Codex write screenshots to `/tmp/e2e-recordings`, the Slack state to `/tmp`, and run `git`/`gh`/`python3`. This is the user's own machine + trusted repo (same full access the Claude `e2e-test` skill has). **Do not point this at untrusted code or a malicious URL** — it runs unsandboxed.
- **`- < prompt.md`** — feed the prompt via stdin (the `-` means "read instructions from stdin"). This EOFs cleanly and avoids the huge-arg escaping problem. Never pass the prompt as an arg while stdin is an open pipe — Codex blocks on "Reading additional input from stdin…".
- **`-c mcp_servers.playwright.*`** — injects Playwright MCP for this run only. Args mirror `~/.claude.json` plus **`--isolated`** (a fresh in-memory browser profile per run). Isolated is required: Playwright MCP's default *persistent* profile takes a filesystem lock, so a run collides ("Browser is already in use … use --isolated") with a concurrent Claude Playwright session or a leftover browser from a prior run. The E2E flow logs in fresh every run anyway, so an ephemeral profile costs nothing and buys clean isolation.
- **`-e`/`-m` from Step 2** map to `model_reasoning_effort` and `-m`.

For `--dry-run`, print the assembled command + `$RUN_DIR/prompt.md` path and stop.

Then monitor `$RUN_DIR/run.log` until the background process exits (Codex streams its reasoning + `mcp: playwright/...` tool lines there; it posts scenario results to Slack itself as it goes). You do not need to stream — just wait for completion and then triage.

## Step 4 — Triage and report back

Codex has already done the run and (unless `--local`) posted the live thread to Slack. Your job is to relay + sanity-check, not re-run anything:

1. **Verdict summary** — parse the final counts from the log (`N ✅ / M ❌ / P ⚠️` and any `[golden]` / 🔁 Healed / 📌 Promoted lines). Lead with them.
2. **Spot-check the load-bearing failures.** Codex can still hallucinate — for any ❌ it reported, glance at the actual code/diff to confirm the claimed contradiction is real before you present it as fact (same discipline as `/confer-with-codex`). Flag any you couldn't confirm as "unverified".
3. **Link the Slack thread** (unless `--local`) so the user can see screenshots/video.
4. **Cost note** — which model + effort ran, so they can tune next time.
5. **Golden-path curation** — if Codex promoted/healed a spec, say which and that the files landed on the branch; if it listed candidates (someone else's PR env), surface them.

Do not dump the raw log — triage it. If the run died early (app unreachable, login failed, Codex auth error), say so with the evidence from the log and stop.

## Fidelity note (say this if asked)

The methodology in `codex-e2e-prompt.md` is a faithful port of the Claude `e2e-test` skill's steps — same target grammar, same "trace every backend change to a frontend surface", same scenario-depth rules, same strict verdicts, same golden-path curation contract, same credential-safety rules, same `e2e/slack_helper.py` calls. Only the execution engine differs, and in exactly two physical ways: (1) the agent loop runs in `codex exec` instead of Claude Code; (2) the browser is driven by Codex calling the Playwright MCP tools (`browser_navigate`, `browser_snapshot`, …) instead of Claude calling them. The one behavioral guard the port ADDS is a hard instruction to use *only* the Playwright MCP tools and never Codex's bundled in-app browser plugin (`node_repl`), which fails headless and would otherwise derail the run.
