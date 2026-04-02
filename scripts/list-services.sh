#!/usr/bin/env bash
#
# list-services.sh — List all registered prototype services with live status
#
# Usage:
#   list-services.sh
#
# Output: JSON array of services with live status check
#

set -euo pipefail

REGISTRY="${HOME}/prototypes/registry.json"

if [ ! -f "$REGISTRY" ] || [ "$(jq 'length' "$REGISTRY")" = "0" ]; then
  echo '[]'
  exit 0
fi

# Use PUBLIC_DOMAIN env var if set, otherwise resolve public IP
if [ -n "${PUBLIC_DOMAIN:-}" ]; then
  HOST="$PUBLIC_DOMAIN"
else
  HOST=$(curl -sf -m 2 http://169.254.169.254/opc/v1/vnics/ 2>/dev/null | jq -r '.[0].publicIp // empty' 2>/dev/null)
  [ -z "$HOST" ] && HOST=$(curl -sf -m 2 ifconfig.me 2>/dev/null)
  [ -z "$HOST" ] && HOST="localhost"
fi

# Check each service's actual status and build output
jq -r 'to_entries[] | "\(.key)\t\(.value.port)\t\(.value.pid)\t\(.value.dir)\t\(.value.command)\t\(.value.started_at)"' "$REGISTRY" | \
while IFS=$'\t' read -r name port pid dir cmd started_at; do
  if [ -n "$pid" ] && [ "$pid" != "null" ] && kill -0 "$pid" 2>/dev/null; then
    status="running"
  else
    status="stopped"
  fi
  jq -n \
    --arg name "$name" \
    --arg port "$port" \
    --arg pid "$pid" \
    --arg dir "$dir" \
    --arg cmd "$cmd" \
    --arg status "$status" \
    --arg started_at "$started_at" \
    --arg url "$([ -d /etc/nginx/conf.d/prototypes ] && echo "https://${HOST}/${name}/" || echo "http://${HOST}:${port}")" \
    '{name: $name, port: ($port | tonumber), pid: $pid, dir: $dir, command: $cmd, status: $status, started_at: $started_at, url: $url}'
done | jq -s '.'
