#!/usr/bin/env bash
#
# guardian.sh — Keep the Keypal bot alive, auto-restart on crash
#
# Usage:
#   guardian.sh [--channel <channel>] [--max-restarts <n>] [--cooldown <seconds>]
#
# Options:
#   --channel        Channel to run (default: all)
#   --max-restarts   Max restarts before giving up (default: 10, 0 = unlimited)
#   --cooldown       Seconds to wait between restarts (default: 5)
#
# This script runs in the foreground and restarts the bot on crash.
# Use with nohup or systemd for background operation.
#

set -uo pipefail

CHANNEL="all"
MAX_RESTARTS=10
COOLDOWN=5
PROJECT_DIR="${HOME}/Workspace/projects/keypal"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --channel) CHANNEL="$2"; shift 2 ;;
    --max-restarts) MAX_RESTARTS="$2"; shift 2 ;;
    --cooldown) COOLDOWN="$2"; shift 2 ;;
    --project-dir) PROJECT_DIR="$2"; shift 2 ;;
    *) shift ;;
  esac
done

LOG_DIR="${HOME}/logs/keypal"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/guardian.log"

log() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $*" | tee -a "$LOG_FILE"; }

send_telegram() {
  local text="$1"
  local token="${TG_BOT_TOKEN:-}"
  local chat_id="${ALLOWED_TG_USERS%%,*}"
  [ -n "$token" ] && [ -n "$chat_id" ] || return 0
  curl -s -X POST "https://api.telegram.org/bot${token}/sendMessage" \
    -d chat_id="$chat_id" -d parse_mode="Markdown" -d text="$text" > /dev/null 2>&1 || true
}

RESTART_COUNT=0

cd "$PROJECT_DIR" || { log "ERROR: Cannot cd to $PROJECT_DIR"; exit 1; }

log "Guardian started (channel=$CHANNEL, max_restarts=$MAX_RESTARTS, cooldown=$COOLDOWN)"

while true; do
  log "Starting bot (attempt $((RESTART_COUNT + 1)))..."

  uv run python -m keypal --channel "$CHANNEL" >> "${LOG_DIR}/${CHANNEL}.log" 2>&1
  EXIT_CODE=$?

  if [ $EXIT_CODE -eq 0 ]; then
    log "Bot exited cleanly (code 0). Stopping guardian."
    break
  fi

  RESTART_COUNT=$((RESTART_COUNT + 1))
  log "Bot crashed (exit code $EXIT_CODE, restart #$RESTART_COUNT)"

  LAST_LOG=$(tail -30 "${LOG_DIR}/${CHANNEL}.log" 2>/dev/null || echo "(no logs)")

  # Notify via Telegram
  send_telegram "⚠️ *Bot crashed*
Exit code: \`${EXIT_CODE}\`
Restart: #${RESTART_COUNT}
Spawning auto-repair..."

  # Spawn Claude Code to diagnose and fix immediately
  if command -v claude >/dev/null 2>&1; then
    log "Running Claude Code auto-repair..."
    DIAGNOSIS=$(claude --print --model sonnet "The Keypal bot just crashed (exit code ${EXIT_CODE}).

Last 30 lines of log:
\`\`\`
${LAST_LOG}
\`\`\`

Project directory: ${PROJECT_DIR}

Please:
1. Diagnose what went wrong
2. Fix the code if possible
3. The bot will be auto-restarted after your fix" 2>/dev/null || echo "Auto-repair unavailable")

    log "Auto-repair result: $(echo "$DIAGNOSIS" | head -5)"
    send_telegram "🔧 *Auto-repair: bot*

${DIAGNOSIS}"
  fi

  # Check restart limit
  if [ "$MAX_RESTARTS" -gt 0 ] && [ "$RESTART_COUNT" -ge "$MAX_RESTARTS" ]; then
    log "Max restarts ($MAX_RESTARTS) reached. Giving up."
    send_telegram "💀 *Bot stopped*
Reached max restarts (${MAX_RESTARTS}). Manual intervention needed."
    exit 1
  fi

  sleep "$COOLDOWN"
done
