#!/usr/bin/env bash
#
# install-mcp.sh — Install and register an MCP server
#
# Writes to the project's .mcp.json (Claude Code native format).
# This ensures MCPs are visible to both the bot SDK and /mcp command.
#
# Usage:
#   install-mcp.sh <name> <command> [args...]
#
# Examples:
#   install-mcp.sh browser npx @anthropic-ai/mcp-browser
#   install-mcp.sh playwright npx -y @playwright/mcp@latest
#   install-mcp.sh filesystem npx @anthropic-ai/mcp-filesystem /home/user
#
# Output: JSON with status (includes warmup results)
#

set -euo pipefail

NAME="${1:?Usage: install-mcp.sh <name> <command> [args...]}"
shift
COMMAND="${1:?Usage: install-mcp.sh <name> <command> [args...]}"
shift
ARGS=("${@}")

# Resolve project directory (script may be symlinked)
SCRIPT_REAL="$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")"
PROJECT_DIR="$(cd "$(dirname "$SCRIPT_REAL")/.." && pwd)"

# Native .mcp.json in project root (where Claude Code reads from)
MCP_FILE="${PROJECT_DIR}/.mcp.json"

result() {
  local status="$1" message="$2" warmup="${3:-}"
  if [ -n "$warmup" ]; then
    jq -n --arg status "$status" --arg name "$NAME" --arg message "$message" --arg warmup "$warmup" \
      '{status: $status, name: $name, message: $message, warmup: $warmup}'
  else
    jq -n --arg status "$status" --arg name "$NAME" --arg message "$message" \
      '{status: $status, name: $name, message: $message}'
  fi
  [ "$status" = "ok" ] && exit 0 || exit 1
}

# Initialize .mcp.json if missing
[ -f "$MCP_FILE" ] || echo '{"mcpServers":{}}' > "$MCP_FILE"

# Check if already registered
EXISTS=$(jq -r --arg n "$NAME" '.mcpServers[$n] // null' "$MCP_FILE")
if [ "$EXISTS" != "null" ]; then
  result "ok" "MCP server '$NAME' already registered"
fi

# Build args JSON array (handle empty args safely)
if [ ${#ARGS[@]} -gt 0 ]; then
  ARGS_JSON=$(printf '%s\n' "${ARGS[@]}" | jq -R . | jq -s '.')
else
  ARGS_JSON='[]'
fi

# Register in .mcp.json (Claude Code native format)
UPDATED=$(jq --arg n "$NAME" --arg cmd "$COMMAND" --argjson args "$ARGS_JSON" '
  .mcpServers[$n] = {type: "stdio", command: $cmd, args: $args}
' "$MCP_FILE")
echo "$UPDATED" > "$MCP_FILE"

# --- Dependency warmup ---
WARMUP_LOG=""

if [ "$COMMAND" = "npx" ] && [ ${#ARGS[@]} -gt 0 ]; then
  # Find the package name (skip flags like -y)
  PKG=""
  for arg in "${ARGS[@]}"; do
    case "$arg" in
      -*) continue ;;
      *) PKG="$arg"; break ;;
    esac
  done

  if [ -n "$PKG" ]; then
    WARMUP_LOG="Pre-installing npm package: $PKG"
    if npm ls -g "$PKG" >/dev/null 2>&1; then
      WARMUP_LOG="$WARMUP_LOG ... already installed"
    else
      if npm install -g "$PKG" >/dev/null 2>&1; then
        WARMUP_LOG="$WARMUP_LOG ... installed"
      else
        WARMUP_LOG="$WARMUP_LOG ... install failed (will download on first use)"
      fi
    fi

    # Known extra dependencies
    case "$PKG" in
      *playwright*|*browser*)
        WARMUP_LOG="$WARMUP_LOG; Installing Chromium for browser automation"
        if npx playwright install chromium >/dev/null 2>&1; then
          WARMUP_LOG="$WARMUP_LOG ... done"
        else
          WARMUP_LOG="$WARMUP_LOG ... failed (will download on first use)"
        fi
        ;;
    esac
  fi
fi

result "ok" "MCP server '$NAME' registered in .mcp.json (command: $COMMAND). Restart bot to activate." "$WARMUP_LOG"
