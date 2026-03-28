#!/usr/bin/env bash
#
# install-plugin.sh — Install a Claude Code plugin from a marketplace
#
# Usage:
#   install-plugin.sh <plugin-name> [marketplace-name] [scope]
#
# Output: JSON object with status and details (designed for Claude Code to parse)
#

set -euo pipefail

PLUGIN_NAME="${1:?}"
MARKETPLACE="${2:-claude-plugins-official}"
SCOPE="${3:-user}"

CLAUDE_DIR="${HOME}/.claude"
MARKETPLACE_DIR="${CLAUDE_DIR}/plugins/marketplaces/${MARKETPLACE}"
MARKETPLACE_JSON="${MARKETPLACE_DIR}/.claude-plugin/marketplace.json"

# JSON output helper — all output goes through this
result() {
  jq -n \
    --arg status "$1" \
    --arg plugin "$PLUGIN_NAME" \
    --arg marketplace "$MARKETPLACE" \
    --arg scope "$SCOPE" \
    --arg message "$2" \
    --arg plugin_path "${3:-}" \
    --arg settings_path "${4:-}" \
    '{status: $status, plugin: $plugin, marketplace: $marketplace, scope: $scope, message: $message, plugin_path: $plugin_path, settings_path: $settings_path}'
  exit $([ "$1" = "ok" ] && echo 0 || echo 1)
}

# ---------------------------------------------------------------------------
# Validate marketplace — check both marketplaces/ and local directories
# ---------------------------------------------------------------------------

# Also check local plugins directory
LOCAL_MARKETPLACE_DIR="${CLAUDE_DIR}/plugins/local"
LOCAL_MARKETPLACE_JSON="${LOCAL_MARKETPLACE_DIR}/.claude-plugin/marketplace.json"

if [ ! -f "${MARKETPLACE_JSON}" ]; then
  # Try local marketplace if the named marketplace isn't found in marketplaces/
  if [ "${MARKETPLACE}" = "local-plugins" ] && [ -f "${LOCAL_MARKETPLACE_JSON}" ]; then
    MARKETPLACE_DIR="${LOCAL_MARKETPLACE_DIR}"
    MARKETPLACE_JSON="${LOCAL_MARKETPLACE_JSON}"
  else
    result "error" "Marketplace '${MARKETPLACE}' not found"
  fi
fi

# Ensure marketplace is registered in settings.json (extraKnownMarketplaces)
SETTINGS_USER="${CLAUDE_DIR}/settings.json"
[ ! -f "${SETTINGS_USER}" ] && echo '{}' > "${SETTINGS_USER}"

# For non-official marketplaces, ensure they're in extraKnownMarketplaces
if [ "${MARKETPLACE}" != "claude-plugins-official" ]; then
  MARKETPLACE_REGISTERED=$(jq -r --arg m "${MARKETPLACE}" '.extraKnownMarketplaces[$m] // null' "${SETTINGS_USER}")
  if [ "${MARKETPLACE_REGISTERED}" = "null" ]; then
    # Auto-register the marketplace
    UPDATED_SETTINGS=$(jq --arg m "${MARKETPLACE}" --arg p "${MARKETPLACE_DIR}" '
      .extraKnownMarketplaces //= {} |
      .extraKnownMarketplaces[$m] = {source: {source: "directory", path: $p}}
    ' "${SETTINGS_USER}")
    echo "${UPDATED_SETTINGS}" > "${SETTINGS_USER}"
  fi
fi

# Look up plugin
PLUGIN_ENTRY=$(jq -e --arg name "${PLUGIN_NAME}" \
  '.plugins[] | select(.name == $name)' "${MARKETPLACE_JSON}" 2>/dev/null) \
  || result "error" "Plugin '${PLUGIN_NAME}' not found in marketplace '${MARKETPLACE}'"

SOURCE_TYPE=$(echo "${PLUGIN_ENTRY}" | jq -r '
  if (.source | type) == "string" then "local"
  elif .source.source == "url" then "url"
  elif .source.source == "git-subdir" then "git-subdir"
  else "unknown"
  end
')

# Ensure plugin files exist locally
PLUGIN_TARGET="${MARKETPLACE_DIR}/plugins/${PLUGIN_NAME}"

if [ ! -d "${PLUGIN_TARGET}" ]; then
  case "${SOURCE_TYPE}" in
    local)
      LOCAL_PATH=$(echo "${PLUGIN_ENTRY}" | jq -r '.source')
      RESOLVED="${MARKETPLACE_DIR}/${LOCAL_PATH#./}"
      [ -d "${RESOLVED}" ] || result "error" "Local source not found at ${RESOLVED}"
      PLUGIN_TARGET="${RESOLVED}"
      ;;
    url)
      GIT_URL=$(echo "${PLUGIN_ENTRY}" | jq -r '.source.url')
      GIT_SHA=$(echo "${PLUGIN_ENTRY}" | jq -r '.source.sha // empty')
      git clone --depth 1 "${GIT_URL}" "${PLUGIN_TARGET}" 2>/dev/null \
        || result "error" "Failed to clone ${GIT_URL}"
      if [ -n "${GIT_SHA}" ]; then
        (cd "${PLUGIN_TARGET}" && git fetch --depth 1 origin "${GIT_SHA}" && git checkout "${GIT_SHA}") 2>/dev/null || true
      fi
      ;;
    git-subdir)
      GIT_REPO=$(echo "${PLUGIN_ENTRY}" | jq -r '.source.url')
      SUBDIR_PATH=$(echo "${PLUGIN_ENTRY}" | jq -r '.source.path')
      GIT_REF=$(echo "${PLUGIN_ENTRY}" | jq -r '.source.ref // "main"')
      [[ "${GIT_REPO}" != http* ]] && GIT_REPO="https://github.com/${GIT_REPO}.git"
      TMPDIR=$(mktemp -d)
      git clone --depth 1 --branch "${GIT_REF}" "${GIT_REPO}" "${TMPDIR}/repo" 2>/dev/null \
        || { rm -rf "${TMPDIR}"; result "error" "Failed to clone ${GIT_REPO}"; }
      if [ -d "${TMPDIR}/repo/${SUBDIR_PATH}" ]; then
        mkdir -p "$(dirname "${PLUGIN_TARGET}")"
        cp -r "${TMPDIR}/repo/${SUBDIR_PATH}" "${PLUGIN_TARGET}"
      else
        rm -rf "${TMPDIR}"
        result "error" "Subdir '${SUBDIR_PATH}' not found in repo"
      fi
      rm -rf "${TMPDIR}"
      ;;
    *)
      result "error" "Unknown source type: ${SOURCE_TYPE}"
      ;;
  esac
fi

# Enable in settings.json
PLUGIN_KEY="${PLUGIN_NAME}@${MARKETPLACE}"

case "${SCOPE}" in
  user)    SETTINGS_FILE="${CLAUDE_DIR}/settings.json" ;;
  project) SETTINGS_FILE=".claude/settings.json" ;;
  local)   SETTINGS_FILE=".claude/settings.local.json" ;;
  *)       result "error" "Invalid scope '${SCOPE}'" ;;
esac

[ ! -f "${SETTINGS_FILE}" ] && mkdir -p "$(dirname "${SETTINGS_FILE}")" && echo '{}' > "${SETTINGS_FILE}"

ALREADY_ENABLED=$(jq -r --arg key "${PLUGIN_KEY}" '.enabledPlugins[$key] // false' "${SETTINGS_FILE}")

if [ "${ALREADY_ENABLED}" != "true" ]; then
  UPDATED=$(jq --arg key "${PLUGIN_KEY}" '.enabledPlugins //= {} | .enabledPlugins[$key] = true' "${SETTINGS_FILE}")
  echo "${UPDATED}" > "${SETTINGS_FILE}"
fi

result "ok" "Plugin '${PLUGIN_NAME}' installed and enabled (scope: ${SCOPE}). Run /reload-plugins to activate." "${PLUGIN_TARGET}" "${SETTINGS_FILE}"
