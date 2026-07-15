---
name: codex-adversarial-review
description: Run an adversarial, multi-agent code review on OpenAI Codex instead of Claude — find → adversarially verify → synthesize, mirroring /code-review ultra's shape. All review reasoning runs on `codex exec` (OpenAI credits); Claude only launches the orchestrator and triages the result, so Claude-token cost is minimal. Use to review the current diff, a branch, or a commit while divesting review spend from Anthropic. Supports --uncommitted / --base / --commit and cost-tuning flags.
argument-hint: "[--uncommitted | --base <branch> | --commit <sha>] [-k N] [--verify-model M] [-d dims]"
---

You are launching an **adversarial code review that runs on OpenAI Codex, not Claude**. The heavy reasoning (N dimension-finders + K skeptics per finding + synthesis) all happens inside `codex exec` calls spawned by an orchestrator script. Your job is only to: pick the diff source, run the orchestrator, then triage its output for the user. Keep your own token use lean — the point of this skill is to move review spend off Anthropic.

## Orchestrator

`~/.codex/tools/adversarial-review.mjs` — zero-dep Node script; a **1:1 port** of Claude Code's `/code-review` (incl. `ultra`) harness, every prompt string lifted **verbatim** from the Claude binary. Stages: **FIND** (one finder per *angle* — correctness A–E: line-scan / removed-behavior / cross-file / language-pitfall / wrapper-proxy; cleanup: Reuse / Simplification / Efficiency / Altitude / Conventions-CLAUDE.md — 8 finders med/high, 10 xhigh/max) → **semantic dedup** (same line/mechanism, keep most concrete, correctness outranks) → **VERIFY** (one verifier per candidate, 3-state `CONFIRMED|PLAUSIBLE|REFUTED` with the per-tier definition — precision `jOo` at medium, recall `WOo` at high — keep CONFIRMED+PLAUSIBLE) → **SWEEP** (xhigh/max: fresh gap-finder) → ranked `review.md` + `findings.json` (findings.json matches the `ReportFindings` input schema exactly). Every `codex exec` is read-only + `--ephemeral`.

Effort tiers mirror the inline cells exactly: `low` 1 pass no verify ≤4 · `medium` 8 angles precision ≤8 · `high` 8 angles recall ≤10 · `xhigh`/`max` 10 angles + sweep ≤15.

## Install (fresh machine)

The orchestrator is version-controlled here as `adversarial-review.mjs`; the runtime path `~/.codex/tools/adversarial-review.mjs` is a symlink to it (single source of truth). On a machine that has synced this repo but not the symlink:

```sh
mkdir -p ~/.codex/tools ~/.codex/prompts
ln -sf "$HOME/.claude/skills/codex-adversarial-review/adversarial-review.mjs" ~/.codex/tools/adversarial-review.mjs
cp "$HOME/.claude/skills/codex-adversarial-review/codex-prompt.md" ~/.codex/prompts/adversarial-review.md   # optional: native /adversarial-review slash-command
```

Requires the `codex` CLI logged in (`codex login`). `codex-prompt.md` is the lightweight single-agent variant for interactive Codex sessions.

## Step 1 — Precheck

```sh
command -v codex >/dev/null || { echo "codex CLI not installed"; exit 1; }
test -f ~/.codex/tools/adversarial-review.mjs || { echo "orchestrator missing at ~/.codex/tools/adversarial-review.mjs"; exit 1; }
```

If a later run fails with an auth error, tell the user to run `codex login` themselves (interactive — you can't) and stop.

## Step 2 — Resolve the diff source and flags

Map the user's argument to exactly one diff source (default `--uncommitted` if none given and the working tree is dirty; otherwise ask or default to `--base main`):

- no arg / "my changes" / "before I push" → `--uncommitted`
- "vs main" / "this branch" / a branch name → `--base <branch>`
- a commit SHA / "that commit" → `--commit <sha>`

Engine (`--engine`, default `orchestrated`):
- `orchestrated` — this script fans out one `codex exec` per angle. Deterministic (exact angle count/caps/dedup), cheaper (no main-agent overhead), robust structured output. The Claude **`ultra` workflow** analog. Default; use for reliability + cost.
- `native` — ONE `codex exec` drives the fan-out through Codex's own `spawn_agent`/`wait_agent` sub-agents (verified working, incl. gpt-5.5 @ high; default now gpt-5.6-sol). The Claude **inline `/code-review`** analog: one process, model-driven. Non-deterministic spawn count + main-agent token overhead; needs a capable main model (gpt-5.6-sol or gpt-5.5 — the mini fumbles the spawn protocol) and runs non-`--ephemeral` under `--full-auto`. **Security:** native needs workspace-write (Codex's multi-agent runtime persists rollouts; read-only breaks spawn), so do NOT run `native` on untrusted code — use `orchestrated` (read-only) for that. Use `native` when you want the single-process/native-subagent architecture on code you trust.

Cost/rigor flags (surface these when the user is cost-conscious — they are):
- `-e <tier>` low|medium|high|xhigh|max (default high) — drives angle count + caps + whether sweep runs
- `--verify-model gpt-5.4-mini` run verifiers on the cheap model
- `-k N` verifier votes per candidate (default 1 = Claude-faithful; >1 keeps unless majority REFUTED — extra rigor, more cost)
- `-m <model>` finder model (default gpt-5.6-sol — Sol is the deep-reasoning tier of the GPT-5.6 family; requires codex-cli >= 0.144, on a "requires a newer version of Codex" 400 run `codex update`. Pass `-m gpt-5.5` to pin the previous model)
- `--dry-run` print plan + call count, spend nothing

**Always run `--dry-run` first if the user hasn't run this before or the diff is large**, and show them the planned call count before spending.

## Step 3 — Run (single Bash call)

Set the Bash tool `timeout` generously — a full gpt-5.6-sol @ high run is minutes (600000+; more for big diffs or high `-k`). Run from the repo you want reviewed (`-C` defaults to cwd; pass `-C <path>` for a worktree/other repo).

```sh
node ~/.codex/tools/adversarial-review.mjs <diff-source> [flags]
```

The script streams progress to stderr and prints the final markdown report to stdout. Artifacts (`review.md`, `findings.json`, `diff.patch`) land in `.codex-review/<timestamp>/`.

## Step 4 — Triage and report back

The findings already survived Codex's own adversarial verification, but Codex can still hallucinate — **spot-check the load-bearing ones against the real code before presenting them as fact** (same discipline as `/confer-with-codex`). Then give the user:

1. **Confirmed findings**, most severe first — `[SEVERITY] title` · `file:line` · one-line why + failure scenario. Flag any you couldn't verify against the code as "unverified".
2. **Dropped candidates** count (N found → M confirmed) so they see the adversarial filter worked.
3. **Cost note** — which model(s)/effort ran, so they can tune next time.
4. **Next action** — offer `--fix`-style manual follow-up, or narrowing dimensions if it was noisy.

Do not just dump the raw report — triage it. Do not let Codex edit files (the orchestrator is read-only by construction; keep it that way).

## Fidelity note (say this if asked)

The finder angles, effort cells, bias lines, 3-state verify definitions, sweep phase, and dedup/ranking rules are **verbatim from the Claude Code binary's `/code-review` prompts** (extracted from the compiled bundle), and the per-tier structure (angle count, per-angle caps, findings caps, which verify variant) matches the inline harness exactly. `ultra` is these same angles + verify fanned out as a background workflow — this reproduces that fan-out. Only two deltas remain, both **physical, not methodological**: (1) it fans out `codex exec` processes in place of Claude's subagent tool; (2) it emits `findings.json` (matching the `ReportFindings` input schema field-for-field) instead of *calling* that tool, which exists only inside Claude Code. Security lives inside the correctness angles (esp. Angle D, language pitfalls), not a separate track — exactly as in the original.
