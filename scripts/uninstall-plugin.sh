#!/usr/bin/env bash
#
# uninstall-plugin.sh — Disable a Claude Code plugin
#
# Usage:
#   uninstall-plugin.sh <plugin-name> [marketplace-name] [scope]
#
# Output: JSON with status and details
#

set -euo pipefail

PLUGIN_NAME="${1:?Usage: uninstall-plugin.sh <plugin-name> [marketplace] [scope]}"
MARKETPLACE="${2:-claude-plugins-official}"
SCOPE="${3:-user}"

CLAUDE_DIR="${HOME}/.claude"
PLUGIN_KEY="${PLUGIN_NAME}@${MARKETPLACE}"

result() {
  jq -n --arg status "$1" --arg plugin "$PLUGIN_NAME" --arg marketplace "$MARKETPLACE" --arg scope "$SCOPE" --arg message "$2" \
    '{status: $status, plugin: $plugin, marketplace: $marketplace, scope: $scope, message: $message}'
  [ "$1" = "ok" ] && exit 0 || exit 1
}

case "${SCOPE}" in
  user)    SETTINGS_FILE="${CLAUDE_DIR}/settings.json" ;;
  project) SETTINGS_FILE=".claude/settings.json" ;;
  local)   SETTINGS_FILE=".claude/settings.local.json" ;;
  *)       result "error" "Invalid scope '${SCOPE}'" ;;
esac

[ -f "${SETTINGS_FILE}" ] || result "error" "Settings file not found: ${SETTINGS_FILE}"

ENABLED=$(jq -r --arg key "$PLUGIN_KEY" '.enabledPlugins[$key] // false' "$SETTINGS_FILE")

if [ "$ENABLED" = "false" ]; then
  result "ok" "Plugin '${PLUGIN_KEY}' is not enabled"
fi

UPDATED=$(jq --arg key "$PLUGIN_KEY" 'del(.enabledPlugins[$key])' "$SETTINGS_FILE")
echo "$UPDATED" > "$SETTINGS_FILE"

result "ok" "Plugin '${PLUGIN_KEY}' disabled (scope: ${SCOPE}). Run /reload-plugins to apply."
