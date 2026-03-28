#!/usr/bin/env bash
#
# uninstall-mcp.sh — Remove an MCP server registration
#
# Usage:
#   uninstall-mcp.sh <name>
#
# Output: JSON with status
#

set -euo pipefail

NAME="${1:?Usage: uninstall-mcp.sh <name>}"
MCP_REGISTRY="${HOME}/.keypal/mcp.json"

result() {
  jq -n --arg status "$1" --arg name "$NAME" --arg message "$2" \
    '{status: $status, name: $name, message: $message}'
  [ "$1" = "ok" ] && exit 0 || exit 1
}

[ -f "$MCP_REGISTRY" ] || result "error" "No MCP registry found"

EXISTS=$(jq -r --arg n "$NAME" '.[$n] // null' "$MCP_REGISTRY")
[ "$EXISTS" != "null" ] || result "ok" "MCP server '$NAME' not registered"

UPDATED=$(jq --arg n "$NAME" 'del(.[$n])' "$MCP_REGISTRY")
echo "$UPDATED" > "$MCP_REGISTRY"

result "ok" "MCP server '$NAME' removed. Restart bot to apply."
