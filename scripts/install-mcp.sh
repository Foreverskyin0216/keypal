#!/usr/bin/env bash
#
# install-mcp.sh — Install and register an MCP server
#
# Usage:
#   install-mcp.sh <name> <command> [args...]
#
# Examples:
#   install-mcp.sh browser npx @anthropic-ai/mcp-browser
#   install-mcp.sh google-calendar npx @anthropic-ai/mcp-google-calendar
#   install-mcp.sh filesystem npx @anthropic-ai/mcp-filesystem /home/user
#
# Output: JSON with status
#

set -euo pipefail

NAME="${1:?Usage: install-mcp.sh <name> <command> [args...]}"
shift
COMMAND="${1:?Usage: install-mcp.sh <name> <command> [args...]}"
shift
ARGS=("$@")

MCP_REGISTRY="${HOME}/.keypal/mcp.json"

result() {
  jq -n --arg status "$1" --arg name "$NAME" --arg message "$2" \
    '{status: $status, name: $name, message: $message}'
  [ "$1" = "ok" ] && exit 0 || exit 1
}

mkdir -p "$(dirname "$MCP_REGISTRY")"
[ -f "$MCP_REGISTRY" ] || echo '{}' > "$MCP_REGISTRY"

# Check if already registered
EXISTS=$(jq -r --arg n "$NAME" '.[$n] // null' "$MCP_REGISTRY")
if [ "$EXISTS" != "null" ]; then
  result "ok" "MCP server '$NAME' already registered"
fi

# Build args JSON array
ARGS_JSON=$(printf '%s\n' "${ARGS[@]}" 2>/dev/null | jq -R . | jq -s '.' 2>/dev/null || echo '[]')

# Register
UPDATED=$(jq --arg n "$NAME" --arg cmd "$COMMAND" --argjson args "$ARGS_JSON" '
  .[$n] = {command: $cmd, args: $args}
' "$MCP_REGISTRY")
echo "$UPDATED" > "$MCP_REGISTRY"

result "ok" "MCP server '$NAME' registered (command: $COMMAND). Restart bot to activate."
