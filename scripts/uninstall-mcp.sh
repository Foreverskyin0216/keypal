#!/usr/bin/env bash
#
# uninstall-mcp.sh — Remove an MCP server registration
#
# Removes from the project's .mcp.json (Claude Code native format).
#
# Usage:
#   uninstall-mcp.sh <name>
#
# Output: JSON with status
#

set -euo pipefail

NAME="${1:?Usage: uninstall-mcp.sh <name>}"

# Resolve project directory (script may be symlinked)
SCRIPT_REAL="$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")"
PROJECT_DIR="$(cd "$(dirname "$SCRIPT_REAL")/.." && pwd)"

MCP_FILE="${PROJECT_DIR}/.mcp.json"

result() {
  jq -n --arg status "$1" --arg name "$NAME" --arg message "$2" \
    '{status: $status, name: $name, message: $message}'
  [ "$1" = "ok" ] && exit 0 || exit 1
}

[ -f "$MCP_FILE" ] || result "error" "No .mcp.json found"

EXISTS=$(jq -r --arg n "$NAME" '.mcpServers[$n] // null' "$MCP_FILE")
[ "$EXISTS" != "null" ] || result "ok" "MCP server '$NAME' not registered"

UPDATED=$(jq --arg n "$NAME" 'del(.mcpServers[$n])' "$MCP_FILE")
echo "$UPDATED" > "$MCP_FILE"

result "ok" "MCP server '$NAME' removed. Restart bot to apply."
