#!/usr/bin/env bash
# codex-agent — run ONE subagent-equivalent unit of work on OpenAI Codex (`codex exec`)
# instead of a Claude subagent, to conserve Anthropic quota near the usage cap.
# Prompt is read from stdin. Edits land in the working dir; the CALLER must `git diff` and
# verify — never trust the output blindly (that verify step is the whole cost model:
# expensive model verifies cheap, Codex generates).
#
# Bash 3.2-safe (macOS system bash): no `set -u` (empty-array expansion trap), pipefail only.
set -o pipefail

# shellcheck source=/dev/null
source "$HOME/.claude/codex-tiers.sh"

WORKDIR="$PWD"
SANDBOX="workspace-write"   # confined writes under WORKDIR; safe superset of read-only work
TIER=""
while [ $# -gt 0 ]; do
  case "$1" in
    --cd)          WORKDIR="$2"; shift 2 ;;
    --tier)        TIER="$2"; shift 2 ;;
    --read-only)   SANDBOX="read-only"; shift ;;
    --full-access) SANDBOX="__bypass__"; shift ;;   # for tasks that build/test outside WORKDIR
    -h|--help)
      echo "usage: codex-agent.sh [--cd DIR] [--tier default|fast|deep|mini] [--read-only|--full-access] < task.md" >&2
      exit 0 ;;
    *) echo "codex-agent: unknown arg: $1" >&2; exit 64 ;;
  esac
done

# Tier precedence: explicit --tier > this session's codex-mode state > 'default'.
if [ -z "$TIER" ]; then
  codex_mode_state
  TIER="$CODEX_TIER"
fi
codex_tier_args "$TIER"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/codex-agent.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
PROMPT="$TMP/task.md"
cat > "$PROMPT"
if [ ! -s "$PROMPT" ]; then echo "codex-agent: empty task on stdin" >&2; exit 64; fi

ARGS=(exec --ephemeral --color never --skip-git-repo-check -C "$WORKDIR"
      -m "$CODEX_MODEL" -c "model_reasoning_effort=\"$CODEX_EFFORT\"")
if [ ${#CODEX_EXTRA_ARGS[@]} -gt 0 ]; then ARGS+=("${CODEX_EXTRA_ARGS[@]}"); fi
if [ "$SANDBOX" = "__bypass__" ]; then
  ARGS+=(--dangerously-bypass-approvals-and-sandbox)
else
  ARGS+=(-s "$SANDBOX")
fi
ARGS+=(-)   # read the prompt from stdin

echo "codex-agent: tier=$TIER model=$CODEX_MODEL effort=$CODEX_EFFORT sandbox=$SANDBOX cd=$WORKDIR" >&2
exec codex "${ARGS[@]}" < "$PROMPT"
