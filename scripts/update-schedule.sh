#!/usr/bin/env bash
#
# update-schedule.sh — Update a scheduled task's cron expression or script
#
# Usage:
#   update-schedule.sh <name> [--cron <expr>] [--script <path>] [--description <text>]
#
# Output: JSON with status and updated values
#

set -euo pipefail

NAME="${1:?Usage: update-schedule.sh <name> [--cron <expr>] [--script <path>] [--description <text>]}"
shift

REGISTRY="${HOME}/schedules/registry.json"
LOG_DIR="${HOME}/schedules/logs"
CRON_TAG="# keypal:${NAME}"

NEW_CRON=""
NEW_SCRIPT=""
NEW_DESC=""

while [ $# -gt 0 ]; do
  case "$1" in
    --cron) NEW_CRON="$2"; shift 2 ;;
    --script) NEW_SCRIPT="$2"; shift 2 ;;
    --description) NEW_DESC="$2"; shift 2 ;;
    *) shift ;;
  esac
done

result() {
  jq -n --arg status "$1" --arg name "$NAME" --arg message "$2" \
    '{status: $status, name: $name, message: $message}'
  [ "$1" = "ok" ] && exit 0 || exit 1
}

[ -f "$REGISTRY" ] || result "error" "No registry found"

EXISTS=$(jq -r --arg n "$NAME" '.[$n] // null' "$REGISTRY")
[ "$EXISTS" != "null" ] || result "error" "Schedule '$NAME' not found"

# Get current values
CURRENT_CRON=$(jq -r --arg n "$NAME" '.[$n].cron' "$REGISTRY")
CURRENT_SCRIPT=$(jq -r --arg n "$NAME" '.[$n].script' "$REGISTRY")

CRON="${NEW_CRON:-$CURRENT_CRON}"
SCRIPT="${NEW_SCRIPT:-$CURRENT_SCRIPT}"

# Resolve new script path if provided
if [ -n "$NEW_SCRIPT" ]; then
  SCRIPT="$(cd "$(dirname "$NEW_SCRIPT")" && pwd)/$(basename "$NEW_SCRIPT")"
  [ -f "$SCRIPT" ] || result "error" "Script not found: $SCRIPT"
  chmod +x "$SCRIPT"
fi

# Update crontab entry
LOG_FILE="${LOG_DIR}/${NAME}.log"
NEW_CRON_LINE="${CRON} ${SCRIPT} >> ${LOG_FILE} 2>&1 ${CRON_TAG}"

CRONTAB_CONTENT=$(crontab -l 2>/dev/null || true)
{ echo "$CRONTAB_CONTENT" | grep -v "$CRON_TAG" || true; echo "$NEW_CRON_LINE"; } | crontab -

# Update registry
UPDATED=$(jq --arg n "$NAME" --arg c "$CRON" --arg s "$SCRIPT" '
  .[$n].cron = $c | .[$n].script = $s | .[$n].status = "active"
' "$REGISTRY")

if [ -n "$NEW_DESC" ]; then
  UPDATED=$(echo "$UPDATED" | jq --arg n "$NAME" --arg d "$NEW_DESC" '.[$n].description = $d')
fi

echo "$UPDATED" > "$REGISTRY"

result "ok" "Schedule '$NAME' updated (cron: ${CRON})"
