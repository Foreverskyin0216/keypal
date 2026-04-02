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

set -o pipefail

CHANNEL="all"
MAX_RESTARTS=10
COOLDOWN=5
SCRIPT_REAL="$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")"
PROJECT_DIR="$(cd "$(dirname "$SCRIPT_REAL")/.." && pwd)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --channel) CHANNEL="$2"; shift 2 ;;
    --max-restarts) MAX_RESTARTS="$2"; shift 2 ;;
    --cooldown) COOLDOWN="$2"; shift 2 ;;
    --project-dir) PROJECT_DIR="$2"; shift 2 ;;
    *) shift ;;
  esac
done

# Source .env if it exists
[ -f "${PROJECT_DIR}/.env" ] && set -a && . "${PROJECT_DIR}/.env" && set +a

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

# Kill any leftover bot/guardian processes (except ourselves)
SELF_PID=$$
for pid in $(pgrep -f "python.*keypal" 2>/dev/null) $(pgrep -f "guardian.sh" 2>/dev/null); do
  [ "$pid" != "$SELF_PID" ] && kill -9 "$pid" 2>/dev/null
done
sleep 1

# --- Dangerous command watcher (background) ---
# Tails the danger log and sends Telegram alerts independently of the bot.
# This catches dangerous commands even if the bot's on_danger callback fails.
DANGER_LOG="${LOG_DIR}/dangerous-commands.log"
DANGER_WATCHER_PID=""

start_danger_watcher() {
  [ -f "$DANGER_LOG" ] || touch "$DANGER_LOG"
  (
    tail -n 0 -f "$DANGER_LOG" 2>/dev/null | while IFS= read -r line; do
      log "DANGER WATCHER: $line"
      send_telegram "🚨 *Dangerous command detected*
\`${line}\`"
    done
  ) &
  DANGER_WATCHER_PID=$!
  log "Danger watcher started (PID=$DANGER_WATCHER_PID)"
}

stop_danger_watcher() {
  if [ -n "$DANGER_WATCHER_PID" ]; then
    kill "$DANGER_WATCHER_PID" 2>/dev/null
    wait "$DANGER_WATCHER_PID" 2>/dev/null
    DANGER_WATCHER_PID=""
  fi
}

trap 'stop_danger_watcher; exit' EXIT INT TERM

start_danger_watcher

log "Guardian started (channel=$CHANNEL, max_restarts=$MAX_RESTARTS, cooldown=$COOLDOWN)"

while true; do
  log "Starting bot (attempt $((RESTART_COUNT + 1)))..."

  uv run python -m keypal --channel "$CHANNEL" >> "${LOG_DIR}/${CHANNEL}.log" 2>&1
  EXIT_CODE=$?

  if [ $EXIT_CODE -eq 0 ]; then
    log "Bot exited (code 0). Restarting..."
    RESTART_COUNT=0
    sleep "$COOLDOWN"
    continue
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
    DIAGNOSIS=$(cd "$PROJECT_DIR" && claude --print --model sonnet --permission-mode bypassPermissions "The Keypal bot just crashed (exit code ${EXIT_CODE}).

Last 30 lines of log:
\`\`\`
${LAST_LOG}
\`\`\`

Project directory: ${PROJECT_DIR}

Please:
1. Diagnose what went wrong
2. Fix the code in this project
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
