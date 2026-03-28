#!/usr/bin/env bash
#
# pause-schedule.sh — Pause a scheduled task (comments out crontab entry)
#
# Usage:
#   pause-schedule.sh <name>
#
# Output: JSON with status
#

set -euo pipefail

NAME="${1:?Usage: pause-schedule.sh <name>}"
REGISTRY="${HOME}/schedules/registry.json"
CRON_TAG="# keypal:${NAME}"

result() {
  jq -n --arg status "$1" --arg name "$NAME" --arg message "$2" \
    '{status: $status, name: $name, message: $message}'
  [ "$1" = "ok" ] && exit 0 || exit 1
}

[ -f "$REGISTRY" ] || result "error" "No registry found"

EXISTS=$(jq -r --arg n "$NAME" '.[$n] // null' "$REGISTRY")
[ "$EXISTS" != "null" ] || result "error" "Schedule '$NAME' not found"

# Comment out the crontab line (prefix with #PAUSED#)
CRONTAB_CONTENT=$(crontab -l 2>/dev/null || true)
if ! echo "$CRONTAB_CONTENT" | grep -q "$CRON_TAG"; then
  result "error" "Crontab entry not found for '$NAME'"
fi

echo "$CRONTAB_CONTENT" | sed "s|^\(.*${CRON_TAG}\)$|#PAUSED# \1|" | crontab -

# Update registry
UPDATED=$(jq --arg n "$NAME" '.[$n].status = "paused"' "$REGISTRY")
echo "$UPDATED" > "$REGISTRY"

result "ok" "Schedule '$NAME' paused"
