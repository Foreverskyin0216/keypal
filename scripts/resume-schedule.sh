#!/usr/bin/env bash
#
# resume-schedule.sh — Resume a paused scheduled task
#
# Usage:
#   resume-schedule.sh <name>
#
# Output: JSON with status
#

set -euo pipefail

NAME="${1:?Usage: resume-schedule.sh <name>}"
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

# Uncomment the crontab line (remove #PAUSED# prefix)
CRONTAB_CONTENT=$(crontab -l 2>/dev/null || true)
echo "$CRONTAB_CONTENT" | sed "s|^#PAUSED# \(.*${CRON_TAG}\)$|\1|" | crontab -

# Update registry
UPDATED=$(jq --arg n "$NAME" '.[$n].status = "active"' "$REGISTRY")
echo "$UPDATED" > "$REGISTRY"

result "ok" "Schedule '$NAME' resumed"
