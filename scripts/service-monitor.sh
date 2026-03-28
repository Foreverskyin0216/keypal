#!/usr/bin/env bash
#
# service-monitor.sh — Monitor a service process and auto-repair on crash
#
# Usage:
#   service-monitor.sh <name> <dir> <port> <command>
#
# This script:
#   1. Runs the service
#   2. If it crashes, immediately:
#      a. Notifies via Telegram
#      b. Spawns Claude Code to diagnose and fix
#      c. Retries up to 3 times
#   3. If all retries fail, marks as dead and notifies
#
# Designed to be started by deploy-prototype.sh via nohup.
#

set -uo pipefail

NAME="${1:?}"
DIR="${2:?}"
PORT="${3:?}"
CMD="${4:?}"

LOG_DIR="${HOME}/prototypes/logs"
LOG_FILE="${LOG_DIR}/${NAME}.log"
REGISTRY="${HOME}/prototypes/registry.json"
MAX_RETRIES=3
COOLDOWN=3

mkdir -p "$LOG_DIR"

send_telegram() {
  local text="$1"
  local token="${TG_BOT_TOKEN:-}"
  local chat_id="${ALLOWED_TG_USERS%%,*}"
  [ -n "$token" ] && [ -n "$chat_id" ] || return 0
  if [ ${#text} -gt 4000 ]; then text="${text:0:4000}..."; fi
  curl -s -X POST "https://api.telegram.org/bot${token}/sendMessage" \
    -d chat_id="$chat_id" -d parse_mode="Markdown" -d text="$text" > /dev/null 2>&1 || true
}

update_registry() {
  local status="$1" pid="$2"
  [ -f "$REGISTRY" ] || return 0
  local updated
  updated=$(jq --arg n "$NAME" --arg s "$status" --arg p "$pid" '
    if .[$n] then .[$n].status = $s | .[$n].pid = ($p | tonumber? // null) else . end
  ' "$REGISTRY")
  echo "$updated" > "$REGISTRY"
}

retry=0

while [ "$retry" -lt "$MAX_RETRIES" ]; do
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) Starting ${NAME} (attempt $((retry + 1))/${MAX_RETRIES})..." >> "$LOG_FILE"

  cd "$DIR"
  env PORT="$PORT" bash -c "$CMD" >> "$LOG_FILE" 2>&1
  EXIT_CODE=$?

  # Clean exit
  if [ $EXIT_CODE -eq 0 ]; then
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) ${NAME} exited cleanly." >> "$LOG_FILE"
    update_registry "stopped" "0"
    exit 0
  fi

  retry=$((retry + 1))
  LAST_LOG=$(tail -30 "$LOG_FILE" 2>/dev/null || echo "(no output)")

  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) ${NAME} crashed (exit $EXIT_CODE)." >> "$LOG_FILE"

  # Notify immediately
  send_telegram "⚠️ *Service crashed: ${NAME}*
Exit code: \`${EXIT_CODE}\`
Attempt: ${retry}/${MAX_RETRIES}

Spawning auto-repair..."

  # Spawn Claude Code to diagnose and fix immediately
  if command -v claude >/dev/null 2>&1; then
    DIAGNOSIS=$(claude --print --model sonnet "Service '${NAME}' just crashed (exit code ${EXIT_CODE}, port ${PORT}, dir: ${DIR}).

Last 30 lines of log:
\`\`\`
${LAST_LOG}
\`\`\`

Please:
1. Diagnose what went wrong
2. Fix the code if possible (files are in ${DIR})
3. The service will be auto-restarted after your fix" 2>/dev/null || echo "Auto-repair unavailable")

    send_telegram "🔧 *Auto-repair: ${NAME}*

${DIAGNOSIS}"
  fi

  if [ "$retry" -lt "$MAX_RETRIES" ]; then
    sleep "$COOLDOWN"
  fi
done

# All retries exhausted
update_registry "dead" "0"
send_telegram "💀 *Service dead: ${NAME}*
Failed after ${MAX_RETRIES} attempts. Manual intervention needed."

exit 1
