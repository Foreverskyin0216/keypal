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
# Output: JSON with status (includes warmup results)
#

set -euo pipefail

NAME="${1:?Usage: install-mcp.sh <name> <command> [args...]}"
shift
COMMAND="${1:?Usage: install-mcp.sh <name> <command> [args...]}"
shift
ARGS=("${@}")

MCP_REGISTRY="${HOME}/.keypal/mcp.json"

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

mkdir -p "$(dirname "$MCP_REGISTRY")"
[ -f "$MCP_REGISTRY" ] || echo '{}' > "$MCP_REGISTRY"

# Check if already registered
EXISTS=$(jq -r --arg n "$NAME" '.[$n] // null' "$MCP_REGISTRY")
if [ "$EXISTS" != "null" ]; then
  result "ok" "MCP server '$NAME' already registered"
fi

# Build args JSON array (handle empty args safely)
if [ ${#ARGS[@]} -gt 0 ]; then
  ARGS_JSON=$(printf '%s\n' "${ARGS[@]}" | jq -R . | jq -s '.')
else
  ARGS_JSON='[]'
fi

# Register in registry
UPDATED=$(jq --arg n "$NAME" --arg cmd "$COMMAND" --argjson args "$ARGS_JSON" '
  .[$n] = {command: $cmd, args: $args}
' "$MCP_REGISTRY")
echo "$UPDATED" > "$MCP_REGISTRY"

# --- Dependency warmup ---
# Pre-download npm packages and known extra dependencies so the first real
# invocation doesn't surprise the user with silent background downloads.

WARMUP_LOG=""

# For npx-based MCPs, pre-install the npm package globally
if [ "$COMMAND" = "npx" ] && [ ${#ARGS[@]} -gt 0 ]; then
  PKG="${ARGS[0]}"
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

result "ok" "MCP server '$NAME' registered (command: $COMMAND). Restart bot to activate." "$WARMUP_LOG"
