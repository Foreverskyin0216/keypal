#!/usr/bin/env bash
#
# list-mcp.sh — List registered MCP servers
#
# Output: JSON array of MCP servers
#

set -euo pipefail

MCP_REGISTRY="${HOME}/.keypal/mcp.json"

if [ ! -f "$MCP_REGISTRY" ] || [ "$(jq 'length' "$MCP_REGISTRY")" = "0" ]; then
  echo '[]'
  exit 0
fi

jq 'to_entries | map({name: .key, command: .value.command, args: .value.args, env: (.value.env // {})})' "$MCP_REGISTRY"
