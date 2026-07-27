#!/usr/bin/env bash
# run-opencode.sh — launch a non-interactive opencode run with logging,
# auto-permissions, and resume support.
#
# Usage:
#   run-opencode.sh [-C dir] [-m provider/model] [-v variant] [-l label]
#                   [--resume <session-id>] [--fork] [--agent <name>]
#                   [-f <file>]... [--no-auto]
#                   <prompt | ->
#
# The prompt is a single argument, or "-" to read it from stdin (preferred for
# multi-line briefs). Prints RUN_DIR=<dir> on stdout; artifacts land there:
#   prompt.md  events.jsonl  last_message.txt  stderr.log  session_id  meta.json
set -euo pipefail

MODEL="${OPENCODE_ROUTER_MODEL:-}"
VARIANT="${OPENCODE_ROUTER_VARIANT:-}"
WORKDIR="$PWD"
LABEL="run"
RESUME=""
FORK=0
AGENT=""
AUTO=1
declare -a FILES=()

usage() { sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; }
die() { echo "run-opencode.sh: $*" >&2; exit 2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -C|--cd)       WORKDIR="$2"; shift 2 ;;
    -m|--model)    MODEL="$2"; shift 2 ;;
    -v|--variant)  VARIANT="$2"; shift 2 ;;
    -l|--label)    LABEL="$2"; shift 2 ;;
    --resume)      RESUME="$2"; shift 2 ;;
    --fork)        FORK=1; shift ;;
    --agent)       AGENT="$2"; shift 2 ;;
    -f|--file)     FILES+=(-f "$2"); shift 2 ;;
    --no-auto)     AUTO=0; shift ;;
    -h|--help)     usage; exit 0 ;;
    --)            shift; break ;;
    -)             break ;;
    -*)            echo "run-opencode.sh: unknown flag: $1" >&2; usage >&2; exit 2 ;;
    *)             break ;;
  esac
done

[[ $# -ge 1 ]] || die "missing prompt (use '-' for stdin)"
command -v opencode >/dev/null || die "opencode CLI not found — see https://opencode.ai"
[[ -d "$WORKDIR" ]] || die "working directory does not exist: $WORKDIR"

RUNS_ROOT="${OPENCODE_ROUTER_RUNS:-${TMPDIR:-/tmp}/opencode-router}"
RUN_DIR="$RUNS_ROOT/$(date +%Y%m%d-%H%M%S)-${LABEL}-$$"
mkdir -p "$RUN_DIR"

if [[ "$1" == "-" ]]; then cat > "$RUN_DIR/prompt.md"; else printf '%s\n' "$1" > "$RUN_DIR/prompt.md"; fi
[[ -s "$RUN_DIR/prompt.md" ]] || die "empty prompt"

args=(opencode run
  --format json
  --dir "$WORKDIR"
  --title "$LABEL"
)
[[ $AUTO -eq 1 ]] && args+=(--auto)
[[ -n "$MODEL" ]]   && args+=(-m "$MODEL")
[[ -n "$VARIANT" ]] && args+=(--variant "$VARIANT")
[[ -n "$AGENT" ]]   && args+=(--agent "$AGENT")
[[ -n "$RESUME" ]]  && args+=(-s "$RESUME")
[[ $FORK -eq 1 ]]   && args+=(--fork)
[[ ${#FILES[@]} -gt 0 ]] && args+=("${FILES[@]}")

PROMPT_TEXT="$(cat "$RUN_DIR/prompt.md")"
args+=("$PROMPT_TEXT")

echo "RUN_DIR=$RUN_DIR"
echo "model=${MODEL:-<opencode default>} variant=${VARIANT:-<default>} workdir=$WORKDIR${RESUME:+ resume=$RESUME}"

set +e
"${args[@]}" > "$RUN_DIR/raw.log" 2> "$RUN_DIR/stderr.log"
status=$?
set -e

grep '^{' "$RUN_DIR/raw.log" > "$RUN_DIR/events.jsonl" || true

if command -v jq >/dev/null; then
  jq -r 'select(.sessionID) | .sessionID' "$RUN_DIR/events.jsonl" 2>/dev/null | head -1 > "$RUN_DIR/session_id" || true
  jq -j 'select(.type=="text") | .text // .data // empty' "$RUN_DIR/events.jsonl" > "$RUN_DIR/last_message.txt" 2>/dev/null || true
  jq -c 'select(.type=="end" or .type=="done" or .type=="error")' "$RUN_DIR/events.jsonl" 2>/dev/null | tail -1 > "$RUN_DIR/meta.json" || true
fi

if [[ ! -s "$RUN_DIR/session_id" ]]; then
  echo "unknown" > "$RUN_DIR/session_id"
fi
SESSION_ID="$(cat "$RUN_DIR/session_id")"

echo "exit_code=$status"
echo "session_id=$SESSION_ID"
if [[ -s "$RUN_DIR/last_message.txt" ]]; then
  echo "--- last message ---"
  cat "$RUN_DIR/last_message.txt"
else
  echo "--- no final message; stderr tail ---"
  tail -20 "$RUN_DIR/stderr.log" 2>/dev/null || true
fi
exit "$status"
