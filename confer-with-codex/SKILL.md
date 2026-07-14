---
name: confer-with-codex
description: Get a second opinion from OpenAI Codex (GPT-5.6 Sol) on the current approach. Packages a compressed brief — problem, the direction you're taking, the specific question — runs `codex exec` read-only (Codex reads the repo, never edits), then triages its reply claim-by-claim into POINTERS (refinements to fold in), CONFLICTS (decisions it disputes — you adjudicate), or REDESIGN (it rejects the whole approach — stop and check with the user). Supports `--fast` (cheap mini pass) and `--deep` (max xhigh reasoning). Use before committing to a non-trivial design, when stuck, or to pressure-test a risky change.
---

You are conferring with **Codex (OpenAI's CLI agent, model GPT-5.6 Sol)** to get an independent second opinion on the work in progress, then deciding what to do with what it says. Codex is a peer reviewer, not an editor: it reads and reasons, **you** keep ownership of the code and the decision.

## Usage

```
/confer-with-codex                  → infer the question from the current task/approach in this conversation
/confer-with-codex <focus>          → ask about a specific thing, e.g. "the retry/backoff design in append.ts"
/confer-with-codex --diff           → focus the consult on the current uncommitted changes
/confer-with-codex --fast [focus]   → quick sanity check: gpt-5.4-mini, low effort (~seconds, cheap)
/confer-with-codex --deep [focus]   → max reasoning: gpt-5.6-sol, xhigh effort (slow, for hard/high-stakes calls)
```

Default (no flag) = gpt-5.6-sol at **high** effort. Flags compose: `/confer-with-codex --deep --diff`.

## When to use it

- Before committing to a **non-trivial design or approach** (new module, schema change, concurrency/retry, migration).
- When you're **stuck** or weighing two approaches and want an independent read.
- To **pressure-test a risky change** before pushing.

Not for trivial edits or things you're already confident about. One consult per decision — not in a tight loop. Each call spins up a full agent (`--fast` is seconds; default/`--deep` can be minutes).

## Step 1 — Precheck

```sh
command -v codex >/dev/null || { echo "codex CLI not installed"; exit 1; }
```

If a later `codex exec` fails with an auth error, tell the user to run `codex login` themselves (interactive — you can't) and stop.

## Step 2 — Build the brief and run the consult (single Bash call)

Codex runs **inside the repo with read access to the working tree** — point it at file paths and let it read; don't paste large code blobs.

**Run mode is non-negotiable:** `--fast` may run foreground (Bash `timeout: 180000`). Default and `--deep` MUST run with Bash `run_in_background: true` — the foreground timeout hard-caps at 10 min and a killed run wastes the whole consult. For background runs, write the brief and the `-o` reply file to a **persistent** location (the session scratchpad), NOT a `mktemp` dir with `trap` cleanup (the trap deletes the reply if the shell dies); launch, then triage when the completion notification arrives.

Set `MODE` and `WANT_DIFF`, fill the `<...>` placeholders in the heredoc from the conversation, then run:

```sh
set -uo pipefail            # NOT -e: we check $? explicitly below
umask 077
MODE="default"             # "fast" | "deep" | "default"  (per the user's flag)
WANT_DIFF=0                # 1 if --diff

# Persistent dir (session scratchpad) so a killed/backgrounded run never loses the reply.
# Only fast mode (foreground, seconds) may clean up on exit.
CONSULT_DIR="<session scratchpad>/codex-consult-$$"   # substitute the real scratchpad path
mkdir -p "$CONSULT_DIR"
[ "$MODE" = "fast" ] && trap 'rm -rf "$CONSULT_DIR"' EXIT
BRIEF="$CONSULT_DIR/brief.md"; REPLY="$CONSULT_DIR/reply.md"

case "$MODE" in
  fast) MODEL="gpt-5.4-mini"; EFFORT="low" ;;
  deep) MODEL="gpt-5.6-sol";  EFFORT="xhigh" ;;
  *)    MODEL="gpt-5.6-sol";  EFFORT="high" ;;
esac

if REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"; then IS_GIT=1; else REPO_ROOT="$PWD"; IS_GIT=0; fi

# Quoted heredoc: brief content is LITERAL — no $/backtick/$( ) expansion of pasted text.
cat > "$BRIEF" <<'EOF'
# Second-opinion request

## Problem
<1-3 sentences: what we're actually trying to accomplish>

## Current direction
<the approach I'm taking or about to take — concrete and honest, including the parts I'm
unsure about. Name key files/functions so you can read them, e.g.
services/api/src/tools/lists/append.ts:200-260>

## Specific question
<what I actually want your judgment on. e.g. "Is inheriting filter defaults from the last
build right, or does it hide bugs? Would you structure the dedupe differently? What am I missing?">

## Constraints
<invariants NOT up for debate: perf budget, patterns to match, must-not-break behavior,
style. Stops you from "fixing" deliberate choices.>

## How to respond
- Read the named files before answering; do NOT edit files, emit a patch, or run mutating
  commands — read-only inspection only. If a build/test would settle it, name the exact
  command for Claude to run later instead of running it.
- Give your honest assessment — agree, refine, or push back. Cite file:line.
- State which files/line ranges you actually inspected, and flag any claim that is
  speculative vs verified.
- End with these three blocks, in order:
  Tests/checks Claude should run: <commands, or "none">
  Assumptions to verify: <bullets, or "none">
  VERDICT: <AGREE | REFINE | DISAGREE | REDESIGN> — <one-sentence reason>
    AGREE: approach is sound, proceed as-is.
    REFINE: sound overall, concrete improvements/pointers below.
    DISAGREE: you'd decide a specific point differently (say which and why).
    REDESIGN: the whole approach is wrong; here's the alternative you'd take.
EOF

# Optional: attach a bounded, sensitive-path-guarded view of uncommitted changes.
if [ "$WANT_DIFF" = "1" ]; then
  if [ "$IS_GIT" = "0" ]; then
    printf '\n## Uncommitted changes\n(not a git repo — describe the change under "Current direction" above)\n' >> "$BRIEF"
  else
    CHANGED="$(git -C "$REPO_ROOT" status --short)"
    # Sensitive-PATH guard only (it does NOT detect secrets pasted into normal files).
    SENSITIVE_RE='(^|[[:space:]/._-])(\.env|\.envrc|\.npmrc|\.pypirc|\.netrc|id_(rsa|dsa|ecdsa|ed25519)|kubeconfig|secrets?|credentials?|tokens?)([[:space:]/._-]|$)|\.(pem|key|crt|cer|der|p12|pfx|jks|keystore)([[:space:]/._-]|$)'
    if printf '%s\n' "$CHANGED" | grep -iE "$SENSITIVE_RE" >/dev/null; then
      printf '\n## Uncommitted changes\n(diff withheld — touches sensitive paths; paths only)\n```\n%s\n```\n' "$CHANGED" >> "$BRIEF"
    else
      git -C "$REPO_ROOT" --no-pager diff --no-ext-diff --no-textconv HEAD > "$CONSULT_DIR/diff.txt" 2>/dev/null
      { printf '\n## Uncommitted changes\n### status\n```\n%s\n```\n### diffstat\n```\n' "$CHANGED";
        git -C "$REPO_ROOT" --no-pager diff --stat HEAD; printf '```\n'; } >> "$BRIEF"
      if [ "$(wc -c < "$CONSULT_DIR/diff.txt")" -lt 60000 ]; then
        { printf '### diff (vs HEAD; untracked files not shown — name them above if relevant)\n```diff\n'; cat "$CONSULT_DIR/diff.txt"; printf '\n```\n'; } >> "$BRIEF"
      else
        printf '(diff >60KB omitted — inspect the files directly via the paths above)\n' >> "$BRIEF"
      fi
    fi
  fi
fi

# Build args as one array (no empty-array expansion → safe under set -u on old Bash too).
CODEX_ARGS=(exec --ephemeral --sandbox read-only --color never -C "$REPO_ROOT")
[ "$IS_GIT" = "0" ] && CODEX_ARGS+=(--skip-git-repo-check)
CODEX_ARGS+=(-m "$MODEL" -c "model_reasoning_effort=\"$EFFORT\"" -o "$REPLY" -)

codex "${CODEX_ARGS[@]}" < "$BRIEF"
rc=$?                       # don't name this `status` — read-only special var in zsh
if [ "$rc" -ne 0 ]; then echo "codex exec FAILED (exit $rc) — see stderr; do NOT triage"; exit "$rc"; fi
if [ ! -s "$REPLY" ]; then echo "codex returned an EMPTY reply — treat as invalid, do NOT triage"; exit 1; fi
echo "=== CODEX REPLY ==="; cat "$REPLY"
```

Flag notes: `--sandbox read-only` (consults, never edits — never raise it). `--ephemeral` (no persisted session files). `-C` gives Codex the repo as its root. Effort is **always passed explicitly** — the model's/config's own default may differ, so relying on it wouldn't deliver the mode's contract.

Model note: GPT-5.6 ships as `gpt-5.6-sol` / `gpt-5.6-terra` / `gpt-5.6-luna`; Sol is the deep-reasoning tier used here. Requires codex-cli ≥ 0.144 — on a "requires a newer version of Codex" 400, run `codex update` and retry.

## Step 3 — Triage and adjudicate (claim by claim)

Don't defer to Codex's `VERDICT:` line — it's a **hint, not a ruling**. Classify each substantive claim independently and let the **highest-risk verified claim** drive the user-facing outcome (a "REFINE" reply can contain one real "DISAGREE"). **Before adopting anything, verify Codex's load-bearing claims against the real code** — it can hallucinate a flag, a file's behavior, or an API. A claim you can't verify but that's high-impact is **neither adopted nor silently dropped** — record it as a follow-up check to run before you rely on it. If Codex gave no verdict, no citations, or clearly never inspected the target files, treat the consult as **low-confidence/invalid — not AGREE** — and say so.

| Bucket | What it looks like | What you do |
|---|---|---|
| **Pointers** (AGREE / REFINE) | Endorsement, or refinements that improve the direction without changing its shape | Verify each against the code. **Adopt the correct ones, discard the wrong ones with a one-line reason.** No user gate — *unless* a pointer changes public behavior, scope, compatibility, the data model, security posture, or a user-visible tradeoff; then surface it. |
| **Conflicts** (DISAGREE) | Codex would decide a specific point differently | **Adjudicate on the merits** given this codebase and constraints: state both positions, reason about which is right, decide, say why. If close or high-stakes, surface to the user with your recommendation rather than deciding alone. |
| **Redesign** (REDESIGN) | Codex rejects the whole approach and proposes another | **Stop. Do not silently pivot.** Summarize the alternative faithfully, give your honest assessment of whether it's actually better, and **ask the user** before discarding the current direction. A redesign is the user's call. |

## Step 4 — Report back

Tight, faithful summary — not a transcript:

1. **Verdict** — Codex's label + core point in one line, plus your confidence read on the consult.
2. **Pointers taken** — bullets, each with why.
3. **Pointers rejected** — bullets, each with why (so the user can overrule).
4. **Conflicts** — per item: Codex's position, your call, your reasoning; flag any you're escalating.
5. **Redesign (if any)** — the alternative + your assessment + an explicit ask before pivoting.
6. **Follow-ups** — any "tests Claude should run" / "assumptions to verify" you're acting on.
7. **Next action** — proceed / proceed-with-edits / await user decision.

Don't misrepresent Codex to favor your own preference, and don't rubber-stamp it to avoid a fight.

## What you do NOT do

- Don't let Codex edit the working tree (read-only sandbox, always).
- Don't auto-adopt suggestions without checking them against the code.
- Don't trust a claimed flag/API without verifying it exists (e.g. there is no `-a`/`--approval` on `codex exec`).
- Don't hide a disagreement or redesign because it's inconvenient.
- Don't pivot to a full redesign without explicit user sign-off.
- Don't loop: if the consult is inconclusive, report that and ask how to proceed rather than re-consulting repeatedly.
