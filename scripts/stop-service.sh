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

# Kill process and all children (process group)
if kill -0 "$PID" 2>/dev/null; then
  # Try to kill the whole process group
  PGID=$(ps -o pgid= -p "$PID" 2>/dev/null | tr -d ' ')
  if [ -n "$PGID" ] && [ "$PGID" != "1" ]; then
    kill -- -"$PGID" 2>/dev/null || true
  else
    kill "$PID" 2>/dev/null || true
  fi
  sleep 1
  # Force kill anything still alive
  if kill -0 "$PID" 2>/dev/null; then
    if [ -n "$PGID" ] && [ "$PGID" != "1" ]; then
      kill -9 -- -"$PGID" 2>/dev/null || true
    else
      kill -9 "$PID" 2>/dev/null || true
    fi
  fi
fi

# Also kill anything still listening on the port
PORT=$(jq -r --arg n "$NAME" '.[$n].port // empty' "$REGISTRY")
if [ -n "$PORT" ]; then
  fuser -k "$PORT/tcp" 2>/dev/null || true
fi

# Remove nginx location block if it exists
NGINX_CONF="/etc/nginx/conf.d/prototypes/${NAME}.conf"
if [ -f "$NGINX_CONF" ]; then
  rm -f "$NGINX_CONF"
  nginx -t -q 2>/dev/null && sudo systemctl reload nginx 2>/dev/null || true
fi

# Update status in registry
UPDATED=$(jq --arg n "$NAME" '.[$n].status = "stopped" | .[$n].pid = null' "$REGISTRY")
echo "$UPDATED" > "$REGISTRY"

result "ok" "Stopped '$NAME' (files kept)"
