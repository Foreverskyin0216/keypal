#!/usr/bin/env bash
#
# list-mcp.sh — List registered MCP servers
#
# Checks both Claude Code's native .mcp.json and legacy ~/.keypal/mcp.json
#
# Output: JSON array of MCP servers
#

set -euo pipefail

# Resolve project directory (script may be symlinked)
SCRIPT_REAL="$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")"
PROJECT_DIR="$(cd "$(dirname "$SCRIPT_REAL")/.." && pwd)"

# Primary: Claude Code native .mcp.json (project-level, where `claude mcp add` writes)
NATIVE_MCP="${PROJECT_DIR}/.mcp.json"
# Legacy: custom registry (for backward compat)
LEGACY_MCP="${HOME}/.keypal/mcp.json"

RESULTS="[]"

# Read from native .mcp.json (mcpServers key)
if [ -f "$NATIVE_MCP" ]; then
  NATIVE=$(jq -r '
    (.mcpServers // {}) | to_entries | map({
      name: .key,
      command: .value.command,
      args: (.value.args // []),
      env: (.value.env // {}),
      source: "native"
    })
  ' "$NATIVE_MCP" 2>/dev/null || echo '[]')
  RESULTS=$(echo "$RESULTS" "$NATIVE" | jq -s '.[0] + .[1]')
fi

# Read from legacy ~/.keypal/mcp.json (flat key-value format)
if [ -f "$LEGACY_MCP" ] && [ "$(jq 'length' "$LEGACY_MCP" 2>/dev/null)" != "0" ]; then
  LEGACY=$(jq '
    to_entries | map({
      name: .key,
      command: .value.command,
      args: (.value.args // []),
      env: (.value.env // {}),
      source: "legacy"
    })
  ' "$LEGACY_MCP" 2>/dev/null || echo '[]')
  RESULTS=$(echo "$RESULTS" "$LEGACY" | jq -s '.[0] + .[1]')
fi

# Deduplicate by name (native takes priority)
echo "$RESULTS" | jq 'group_by(.name) | map(if length > 1 then (map(select(.source == "native")) | .[0]) // .[0] else .[0] end)'
