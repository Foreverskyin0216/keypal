#!/usr/bin/env bash
#
# list-schedules.sh — List all scheduled tasks with status
#
# Usage:
#   list-schedules.sh
#
# Output: JSON array of scheduled tasks
#

set -euo pipefail

REGISTRY="${HOME}/schedules/registry.json"

if [ ! -f "$REGISTRY" ] || [ "$(jq 'length' "$REGISTRY")" = "0" ]; then
  echo '[]'
  exit 0
fi

# Cross-reference with actual crontab to verify status
CRONTAB_CONTENT=$(crontab -l 2>/dev/null || true)

jq -r 'to_entries[] | "\(.key)"' "$REGISTRY" | \
while read -r name; do
  ENTRY=$(jq --arg n "$name" '.[$n]' "$REGISTRY")
  TAG="# keypal:${name}"

  # Check if active in crontab
  if echo "$CRONTAB_CONTENT" | grep -q "$TAG"; then
    if echo "$CRONTAB_CONTENT" | grep "$TAG" | grep -q "^#[^!]"; then
      LIVE_STATUS="paused"
    else
      LIVE_STATUS="active"
    fi
  else
    LIVE_STATUS="missing"
  fi

  echo "$ENTRY" | jq --arg n "$name" --arg ls "$LIVE_STATUS" '. + {name: $n, live_status: $ls}'
done | jq -s '.'
