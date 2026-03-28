#!/usr/bin/env bash
#
# stop-service.sh — Stop a running prototype service (keeps files)
#
# Usage:
#   stop-service.sh <name>
#
# Output: JSON with status and details
#

set -euo pipefail

NAME="${1:?Usage: stop-service.sh <name>}"
REGISTRY="${HOME}/prototypes/registry.json"

result() {
  jq -n --arg status "$1" --arg name "$NAME" --arg message "$2" \
    '{status: $status, name: $name, message: $message}'
  [ "$1" = "ok" ] && exit 0 || exit 1
}

[ -f "$REGISTRY" ] || result "error" "No registry found"

PID=$(jq -r --arg n "$NAME" '.[$n].pid // empty' "$REGISTRY")

[ -n "$PID" ] || result "error" "Service '$NAME' not found in registry"

# Kill process
if kill -0 "$PID" 2>/dev/null; then
  kill "$PID" 2>/dev/null || true
  sleep 1
  kill -0 "$PID" 2>/dev/null && kill -9 "$PID" 2>/dev/null || true
fi

# Update status in registry
UPDATED=$(jq --arg n "$NAME" '.[$n].status = "stopped" | .[$n].pid = null' "$REGISTRY")
echo "$UPDATED" > "$REGISTRY"

result "ok" "Stopped '$NAME' (files kept)"
