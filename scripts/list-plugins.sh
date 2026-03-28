#!/usr/bin/env bash
#
# list-plugins.sh — List available plugins from a marketplace
#
# Usage:
#   list-plugins.sh [marketplace-name] [--installed-only]
#
# Output: JSON array of plugins with name, description, category, and installed status
#

set -euo pipefail

MARKETPLACE="claude-plugins-official"
FILTER=""

for arg in "$@"; do
  case "${arg}" in
    --installed-only) FILTER="--installed-only" ;;
    --*) ;;
    *) MARKETPLACE="${arg}" ;;
  esac
done

CLAUDE_DIR="${HOME}/.claude"
MARKETPLACE_DIR="${CLAUDE_DIR}/plugins/marketplaces/${MARKETPLACE}"
MARKETPLACE_JSON="${MARKETPLACE_DIR}/.claude-plugin/marketplace.json"
SETTINGS_FILE="${CLAUDE_DIR}/settings.json"

[ -f "${MARKETPLACE_JSON}" ] || { jq -n --arg m "${MARKETPLACE}" '{error: "Marketplace not found", marketplace: $m}'; exit 1; }

# Get enabled plugins from settings
ENABLED_PLUGINS="{}"
if [ -f "${SETTINGS_FILE}" ]; then
  ENABLED_PLUGINS=$(jq '.enabledPlugins // {}' "${SETTINGS_FILE}")
fi

# Build plugin list with installed status
jq --argjson enabled "${ENABLED_PLUGINS}" --arg marketplace "${MARKETPLACE}" '
  .plugins | map({
    name: .name,
    description: .description,
    category: (.category // "other"),
    installed: ($enabled[(.name + "@" + $marketplace)] // false)
  })
  | if "'"${FILTER}"'" == "--installed-only" then map(select(.installed)) else . end
  | sort_by(.category, .name)
' "${MARKETPLACE_JSON}"
