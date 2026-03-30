#!/usr/bin/env bash
#
# watchdog.sh — Decorator for tasks/services: notify + auto-diagnose on failure
#
# Usage:
#   watchdog.sh [options] <command...>
#
# Options:
#   --name <name>         Task/service name for notifications
#   --notify              Send Telegram notification on failure (default: on)
#   --no-notify           Disable Telegram notification
#   --diagnose            Spawn Claude Code to diagnose on failure
#   --no-diagnose         Skip Claude Code diagnosis (default)
#   --fix                 Spawn Claude Code to diagnose AND attempt fix
#   --chat-id <id>        Telegram chat ID to notify (default: from KEYPAL_CHAT_ID env)
#   --max-log <n>         Max lines of output to include (default: 50)
#
# Environment:
#   TG_BOT_TOKEN          Telegram bot token (required for notifications)
#   KEYPAL_CHAT_ID        Default Telegram chat ID to notify
#
# Examples:
#   watchdog.sh --name check-pr ~/schedules/check-pr/task.sh
#   watchdog.sh --name todo-app --diagnose --fix node server.js
#   watchdog.sh --name backup --chat-id 12345 ./backup.sh
#
# How it works:
#   1. Runs the wrapped command
#   2. If exit code == 0: done, no cost
#   3. If exit code != 0:
#      a. Captures stderr/stdout
#      b. Sends Telegram notification (if --notify)
#      c. Runs Claude Code one-shot diagnosis (if --diagnose or --fix)
#      d. Sends diagnosis result to Telegram
#
# Token cost: ZERO when tasks succeed. Only consumes tokens on failure + --diagnose/--fix.
#

set -uo pipefail
# Note: not using -e because we need to capture the wrapped command's exit code

NAME="unknown"
NOTIFY=true
DIAGNOSE=false
FIX=false
CHAT_ID="${ALLOWED_TG_USERS%%,*}"
MAX_LOG=50

# Parse options
while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) NAME="$2"; shift 2 ;;
    --notify) NOTIFY=true; shift ;;
    --no-notify) NOTIFY=false; shift ;;
    --diagnose) DIAGNOSE=true; shift ;;
    --no-diagnose) DIAGNOSE=false; shift ;;
    --fix) DIAGNOSE=true; FIX=true; shift ;;
    --chat-id) CHAT_ID="$2"; shift 2 ;;
    --max-log) MAX_LOG="$2"; shift 2 ;;
    --) shift; break ;;
    -*) echo "Unknown option: $1" >&2; exit 1 ;;
    *) break ;;
  esac
done

[ $# -gt 0 ] || { echo "Usage: watchdog.sh [options] <command...>" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Run the wrapped command, capture output
# ---------------------------------------------------------------------------

TMPLOG=$(mktemp)
"$@" > "$TMPLOG" 2>&1
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
  rm -f "$TMPLOG"
  exit 0
fi

# ---------------------------------------------------------------------------
# Task failed — gather context
# ---------------------------------------------------------------------------

LOG_TAIL=$(tail -n "$MAX_LOG" "$TMPLOG" 2>/dev/null || echo "(no output)")
TIMESTAMP=$(date -u +"%Y-%m-%d %H:%M:%S UTC")

# ---------------------------------------------------------------------------
# Send Telegram notification
# ---------------------------------------------------------------------------

send_telegram() {
  local text="$1"
  local token="${TG_BOT_TOKEN:-}"
  [ -n "$token" ] && [ -n "$CHAT_ID" ] || return 0

  # Telegram max message length is 4096
  if [ ${#text} -gt 4000 ]; then
    text="${text:0:4000}..."
  fi

  curl -s -X POST "https://api.telegram.org/bot${token}/sendMessage" \
    -d chat_id="$CHAT_ID" \
    -d parse_mode="Markdown" \
    -d text="$text" > /dev/null 2>&1 || true
}

if [ "$NOTIFY" = true ]; then
  ALERT_MSG=$(cat <<MSG
⚠️ *Task Failed: ${NAME}*

Exit code: \`${EXIT_CODE}\`
Time: ${TIMESTAMP}

\`\`\`
${LOG_TAIL}
\`\`\`
MSG
)
  send_telegram "$ALERT_MSG"
fi

# ---------------------------------------------------------------------------
# Auto-diagnose with Claude Code (one-shot, only on failure)
# ---------------------------------------------------------------------------

if [ "$DIAGNOSE" = true ] && command -v claude >/dev/null 2>&1; then
  DIAGNOSE_PROMPT="A scheduled task '${NAME}' just failed with exit code ${EXIT_CODE}.

Here is the output:
\`\`\`
${LOG_TAIL}
\`\`\`

Please:
1. Diagnose what went wrong.
2. Suggest a fix."

  if [ "$FIX" = true ]; then
    DIAGNOSE_PROMPT="${DIAGNOSE_PROMPT}
3. Apply the fix if you can."
  fi

  # One-shot query — no session, no ongoing cost
  DIAGNOSIS=$(claude --print --model sonnet --permission-mode bypassPermissions "$DIAGNOSE_PROMPT" 2>/dev/null || echo "Claude Code diagnosis unavailable")

  if [ "$NOTIFY" = true ] && [ -n "$DIAGNOSIS" ]; then
    DIAG_MSG=$(cat <<MSG
🔍 *Auto-Diagnosis: ${NAME}*

${DIAGNOSIS}
MSG
)
    send_telegram "$DIAG_MSG"
  fi
fi

rm -f "$TMPLOG"
exit $EXIT_CODE
