#!/usr/bin/env bash
#
# healthcheck.sh — Check all registered services and notify/fix on failure
#
# Usage:
#   healthcheck.sh [--notify] [--diagnose] [--fix] [--restart]
#
# Options:
#   --notify     Send Telegram notification for dead services (default: on)
#   --diagnose   Spawn Claude Code to diagnose dead services
#   --fix        Diagnose + attempt fix
#   --restart    Auto-restart dead services before diagnosing
#
# Output: JSON summary
#
# Designed to run as a cron job (e.g. every 5 minutes)
#

set -euo pipefail

NOTIFY=true
DIAGNOSE=false
FIX=false
RESTART=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --notify) NOTIFY=true; shift ;;
    --no-notify) NOTIFY=false; shift ;;
    --diagnose) DIAGNOSE=true; shift ;;
    --fix) DIAGNOSE=true; FIX=true; shift ;;
    --restart) RESTART=true; shift ;;
    --no-restart) RESTART=false; shift ;;
    *) shift ;;
  esac
done

REGISTRY="${HOME}/prototypes/registry.json"
LOG_DIR="${HOME}/prototypes/logs"

[ -f "$REGISTRY" ] || { echo '{"status":"ok","checked":0,"dead":0,"restarted":0}'; exit 0; }

CHECKED=0
DEAD=0
RESTARTED=0
DEAD_NAMES=()

send_telegram() {
  local text="$1"
  local token="${TG_BOT_TOKEN:-}"
  local chat_id="${ALLOWED_TG_USERS%%,*}"
  [ -n "$token" ] && [ -n "$chat_id" ] || return 0
  if [ ${#text} -gt 4000 ]; then text="${text:0:4000}..."; fi
  curl -s -X POST "https://api.telegram.org/bot${token}/sendMessage" \
    -d chat_id="$chat_id" -d parse_mode="Markdown" -d text="$text" > /dev/null 2>&1 || true
}

# Check each service
jq -r 'to_entries[] | select(.value.status == "running") | "\(.key)\t\(.value.pid)\t\(.value.dir)\t\(.value.command)\t\(.value.port)"' "$REGISTRY" | \
while IFS=$'\t' read -r name pid dir cmd port; do
  CHECKED=$((CHECKED + 1))

  # Check if process is alive
  if [ -n "$pid" ] && [ "$pid" != "null" ] && kill -0 "$pid" 2>/dev/null; then
    continue
  fi

  # Service is dead
  DEAD=$((DEAD + 1))
  DEAD_NAMES+=("$name")

  LOG_TAIL=""
  [ -f "${LOG_DIR}/${name}.log" ] && LOG_TAIL=$(tail -20 "${LOG_DIR}/${name}.log" 2>/dev/null || true)

  # Try restart
  if [ "$RESTART" = true ] && [ -n "$dir" ] && [ -d "$dir" ]; then
    DEPLOY_RESULT=$("${HOME}/.claude/scripts/deploy-prototype.sh" "$name" "$dir" "$port" "$cmd" 2>&1 || true)
    NEW_STATUS=$(echo "$DEPLOY_RESULT" | jq -r '.status // "error"' 2>/dev/null || echo "error")
    if [ "$NEW_STATUS" = "ok" ]; then
      RESTARTED=$((RESTARTED + 1))
      if [ "$NOTIFY" = true ]; then
        send_telegram "🔄 *Auto-restarted: ${name}*
Service was dead, successfully restarted on port ${port}."
      fi
      continue
    fi
  fi

  # Restart failed or not attempted — notify
  if [ "$NOTIFY" = true ]; then
    send_telegram "💀 *Service down: ${name}*

Port: ${port}
Last log:
\`\`\`
${LOG_TAIL}
\`\`\`"
  fi

  # Diagnose with Claude Code
  if [ "$DIAGNOSE" = true ] && command -v claude >/dev/null 2>&1; then
    PROMPT="Service '${name}' (port ${port}, dir: ${dir}) is down and restart failed.

Last log output:
\`\`\`
${LOG_TAIL}
\`\`\`

Please diagnose the issue."
    if [ "$FIX" = true ]; then
      PROMPT="${PROMPT}
Then fix it and redeploy using: ~/.claude/scripts/deploy-prototype.sh ${name} ${dir} ${port}"
    fi

    DIAGNOSIS=$(claude --print --model sonnet "$PROMPT" 2>/dev/null || echo "Diagnosis unavailable")
    if [ "$NOTIFY" = true ] && [ -n "$DIAGNOSIS" ]; then
      send_telegram "🔍 *Diagnosis: ${name}*

${DIAGNOSIS}"
    fi
  fi
done

jq -n --argjson checked "$CHECKED" --argjson dead "$DEAD" --argjson restarted "$RESTARTED" \
  '{status: "ok", checked: $checked, dead: $dead, restarted: $restarted}'
