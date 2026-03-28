#!/usr/bin/env bash
#
# clear-service.sh — Stop a service and delete all its files
#
# Usage:
#   clear-service.sh <name>
#   clear-service.sh --all
#
# Single service: stops process, removes project directory, removes logs, removes from registry
# --all: clears ALL services (stops all, deletes all files, resets registry)
#
# Output: JSON with status and details
#

set -euo pipefail

TARGET="${1:?Usage: clear-service.sh <name> | clear-service.sh --all}"
REGISTRY="${HOME}/prototypes/registry.json"
LOG_DIR="${HOME}/prototypes/logs"

result() {
  jq -n --arg status "$1" --arg name "$TARGET" --arg message "$2" \
    '{status: $status, name: $name, message: $message}'
  [ "$1" = "ok" ] && exit 0 || exit 1
}

[ -f "$REGISTRY" ] || result "error" "No registry found"

if [ "$TARGET" = "--all" ]; then
  COUNT=$(jq 'length' "$REGISTRY")

  # Stop all processes
  jq -r 'to_entries[] | "\(.value.pid)\t\(.value.dir)"' "$REGISTRY" | \
  while IFS=$'\t' read -r pid dir; do
    if [ -n "$pid" ] && [ "$pid" != "null" ] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
    fi
    if [ -n "$dir" ] && [ -d "$dir" ]; then
      rm -rf "$dir"
    fi
  done

  # Wait for processes to die
  sleep 1

  # Reset registry and logs
  echo '{}' > "$REGISTRY"
  rm -rf "$LOG_DIR"
  mkdir -p "$LOG_DIR"

  jq -n --arg status "ok" --arg name "--all" --arg message "Cleared all ${COUNT} services" \
    '{status: $status, name: $name, message: $message}'
  exit 0
fi

# Single service
PID=$(jq -r --arg n "$TARGET" '.[$n].pid // empty' "$REGISTRY")
DIR=$(jq -r --arg n "$TARGET" '.[$n].dir // empty' "$REGISTRY")

[ -n "$PID" ] || [ -n "$DIR" ] || result "error" "Service '$TARGET' not found"

# Stop process
if [ -n "$PID" ] && [ "$PID" != "null" ] && kill -0 "$PID" 2>/dev/null; then
  kill "$PID" 2>/dev/null || true
  sleep 1
  kill -0 "$PID" 2>/dev/null && kill -9 "$PID" 2>/dev/null || true
fi

# Delete project directory
if [ -n "$DIR" ] && [ -d "$DIR" ]; then
  rm -rf "$DIR"
fi

# Delete logs
rm -f "${LOG_DIR}/${TARGET}.log"

# Remove from registry
UPDATED=$(jq --arg n "$TARGET" 'del(.[$n])' "$REGISTRY")
echo "$UPDATED" > "$REGISTRY"

result "ok" "Cleared '$TARGET' (process stopped, files deleted)"
