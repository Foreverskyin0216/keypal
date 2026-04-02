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

  # Stop all processes and children
  jq -r 'to_entries[] | "\(.value.pid)\t\(.value.port)\t\(.value.dir)"' "$REGISTRY" | \
  while IFS=$'\t' read -r pid port dir; do
    if [ -n "$pid" ] && [ "$pid" != "null" ] && kill -0 "$pid" 2>/dev/null; then
      PGID=$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')
      if [ -n "$PGID" ] && [ "$PGID" != "1" ]; then
        kill -- -"$PGID" 2>/dev/null || true
      else
        kill "$pid" 2>/dev/null || true
      fi
    fi
    [ -n "$port" ] && fuser -k "$port/tcp" 2>/dev/null || true
    if [ -n "$dir" ] && [ -d "$dir" ]; then
      rm -rf "$dir"
    fi
  done

  sleep 1

  # Remove all nginx prototype locations
  rm -f /etc/nginx/conf.d/prototypes/*.conf 2>/dev/null
  nginx -t -q 2>/dev/null && sudo systemctl reload nginx 2>/dev/null || true

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

# Stop process and all children
if [ -n "$PID" ] && [ "$PID" != "null" ] && kill -0 "$PID" 2>/dev/null; then
  PGID=$(ps -o pgid= -p "$PID" 2>/dev/null | tr -d ' ')
  if [ -n "$PGID" ] && [ "$PGID" != "1" ]; then
    kill -- -"$PGID" 2>/dev/null || true
  else
    kill "$PID" 2>/dev/null || true
  fi
  sleep 1
  if kill -0 "$PID" 2>/dev/null; then
    kill -9 "$PID" 2>/dev/null || true
  fi
fi

# Kill anything on the port
PORT=$(jq -r --arg n "$TARGET" '.[$n].port // empty' "$REGISTRY")
if [ -n "$PORT" ]; then
  fuser -k "$PORT/tcp" 2>/dev/null || true
fi

# Delete project directory
if [ -n "$DIR" ] && [ -d "$DIR" ]; then
  rm -rf "$DIR"
fi

# Remove nginx location block
rm -f "/etc/nginx/conf.d/prototypes/${TARGET}.conf" 2>/dev/null
nginx -t -q 2>/dev/null && sudo systemctl reload nginx 2>/dev/null || true

# Delete logs
rm -f "${LOG_DIR}/${TARGET}.log"

# Remove from registry
UPDATED=$(jq --arg n "$TARGET" 'del(.[$n])' "$REGISTRY")
echo "$UPDATED" > "$REGISTRY"

result "ok" "Cleared '$TARGET' (process stopped, files deleted)"
