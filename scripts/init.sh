#!/usr/bin/env bash
#
# init.sh — Pre-flight check before running the Keypal bot
#
# Creates symlinks from ~/.claude/ to repo, ensures all directories,
# plugin registrations, and dependencies are in place.
#
# Usage:
#   scripts/init.sh           (from repo root)
#   ~/.claude/scripts/init.sh (via symlink)
#
# Output: JSON summary of checks performed
#

set -euo pipefail

# Resolve repo root (follow symlinks)
SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd -P)"
# If running from ~/.claude/scripts/ (symlink), resolve to repo
if [ -L "${SCRIPT_PATH}/init.sh" ] 2>/dev/null; then
  REPO_DIR="$(cd "$(dirname "$(readlink "${SCRIPT_PATH}/init.sh")")" && cd .. && pwd)"
else
  REPO_DIR="$(cd "${SCRIPT_PATH}/.." && pwd)"
fi

CLAUDE_DIR="${HOME}/.claude"
SCRIPTS_DIR="${CLAUDE_DIR}/scripts"
PLUGIN_DIR="${CLAUDE_DIR}/plugins/local"
MARKETPLACE_JSON="${PLUGIN_DIR}/.claude-plugin/marketplace.json"
SETTINGS_FILE="${CLAUDE_DIR}/settings.json"

REPO_SCRIPTS="${REPO_DIR}/scripts"
REPO_PLUGINS="${REPO_DIR}/plugins"

ERRORS=()
FIXES=()

log_fix() { FIXES+=("$1"); }
log_error() { ERRORS+=("$1"); }

# ---------------------------------------------------------------------------
# 1. Symlink repo scripts → ~/.claude/scripts/
# ---------------------------------------------------------------------------

if [ -d "$REPO_SCRIPTS" ]; then
  mkdir -p "$SCRIPTS_DIR"
  for script in "${REPO_SCRIPTS}"/*.sh; do
    [ -f "$script" ] || continue
    base="$(basename "$script")"
    target="${SCRIPTS_DIR}/${base}"
    if [ ! -e "$target" ]; then
      ln -sf "$script" "$target"
      log_fix "Linked script: ${base}"
    elif [ ! -L "$target" ]; then
      # Existing non-symlink file — replace with symlink
      ln -sf "$script" "$target"
      log_fix "Re-linked script: ${base}"
    fi
  done
fi

# ---------------------------------------------------------------------------
# 2. Symlink repo plugin-manager → ~/.claude/plugins/local/plugin-manager/
# ---------------------------------------------------------------------------

REPO_PLUGIN_MANAGER="${REPO_PLUGINS}/plugin-manager"
LOCAL_PLUGIN_MANAGER="${PLUGIN_DIR}/plugin-manager"

if [ -d "$REPO_PLUGIN_MANAGER" ]; then
  mkdir -p "$PLUGIN_DIR"
  if [ ! -e "$LOCAL_PLUGIN_MANAGER" ]; then
    ln -sf "$REPO_PLUGIN_MANAGER" "$LOCAL_PLUGIN_MANAGER"
    log_fix "Linked plugin-manager to repo"
  elif [ ! -L "$LOCAL_PLUGIN_MANAGER" ]; then
    rm -rf "$LOCAL_PLUGIN_MANAGER"
    ln -sf "$REPO_PLUGIN_MANAGER" "$LOCAL_PLUGIN_MANAGER"
    log_fix "Re-linked plugin-manager to repo"
  fi
fi

# ---------------------------------------------------------------------------
# 3. Local marketplace manifest
# ---------------------------------------------------------------------------

if [ ! -f "$MARKETPLACE_JSON" ]; then
  mkdir -p "$(dirname "$MARKETPLACE_JSON")"
  if [ -f "${REPO_PLUGINS}/marketplace.json" ]; then
    ln -sf "${REPO_PLUGINS}/marketplace.json" "$MARKETPLACE_JSON"
    log_fix "Linked marketplace.json to repo"
  else
    cat > "$MARKETPLACE_JSON" <<'MARKET'
{
  "name": "local-plugins",
  "description": "Custom local plugins",
  "plugins": [
    {
      "name": "plugin-manager",
      "description": "Browse, explain, and install Claude Code plugins using natural language.",
      "source": "./plugin-manager",
      "category": "productivity"
    }
  ]
}
MARKET
    log_fix "Created local marketplace manifest"
  fi
fi

# ---------------------------------------------------------------------------
# 4. Scripts are executable
# ---------------------------------------------------------------------------

for script in "${SCRIPTS_DIR}"/*.sh; do
  [ -f "$script" ] || continue
  # Resolve symlink to check actual file
  real="$(readlink -f "$script" 2>/dev/null || echo "$script")"
  if [ ! -x "$real" ]; then
    chmod +x "$real"
    log_fix "Made executable: $(basename "$script")"
  fi
done

# ---------------------------------------------------------------------------
# 5. Required directories
# ---------------------------------------------------------------------------

for dir in "${HOME}/prototypes/logs" "${HOME}/schedules/logs"; do
  if [ ! -d "$dir" ]; then
    mkdir -p "$dir"
    log_fix "Created directory: $dir"
  fi
done

# ---------------------------------------------------------------------------
# 6. Registry files exist
# ---------------------------------------------------------------------------

for registry in "${HOME}/prototypes/registry.json" "${HOME}/schedules/registry.json"; do
  if [ ! -f "$registry" ]; then
    mkdir -p "$(dirname "$registry")"
    echo '{}' > "$registry"
    log_fix "Created registry: $registry"
  fi
done

# ---------------------------------------------------------------------------
# 7. Global settings: marketplace registered + plugin enabled
# ---------------------------------------------------------------------------

[ -f "$SETTINGS_FILE" ] || echo '{}' > "$SETTINGS_FILE"

HAS_MARKETPLACE=$(jq -r '.extraKnownMarketplaces["local-plugins"] // null' "$SETTINGS_FILE")
if [ "$HAS_MARKETPLACE" = "null" ]; then
  UPDATED=$(jq --arg p "$PLUGIN_DIR" '
    .extraKnownMarketplaces //= {} |
    .extraKnownMarketplaces["local-plugins"] = {source: {source: "directory", path: $p}}
  ' "$SETTINGS_FILE")
  echo "$UPDATED" > "$SETTINGS_FILE"
  log_fix "Registered local-plugins marketplace in settings.json"
fi

HAS_PLUGIN=$(jq -r '.enabledPlugins["plugin-manager@local-plugins"] // false' "$SETTINGS_FILE")
if [ "$HAS_PLUGIN" != "true" ]; then
  UPDATED=$(jq '.enabledPlugins //= {} | .enabledPlugins["plugin-manager@local-plugins"] = true' "$SETTINGS_FILE")
  echo "$UPDATED" > "$SETTINGS_FILE"
  log_fix "Enabled plugin-manager@local-plugins in settings.json"
fi

# ---------------------------------------------------------------------------
# 8. Patch ralph-loop: default completion-promise = DONE, hooks executable
# ---------------------------------------------------------------------------

RALPH_SETUP="${CLAUDE_DIR}/plugins/marketplaces/claude-plugins-official/plugins/ralph-loop/scripts/setup-ralph-loop.sh"
if [ -f "$RALPH_SETUP" ]; then
  if grep -q 'COMPLETION_PROMISE="null"' "$RALPH_SETUP"; then
    sed -i.bak 's/COMPLETION_PROMISE="null"/COMPLETION_PROMISE="DONE"/' "$RALPH_SETUP"
    rm -f "${RALPH_SETUP}.bak"
    log_fix "Patched ralph-loop default completion-promise to DONE"
  fi
  RALPH_HOOKS_DIR="$(dirname "$RALPH_SETUP")/../hooks"
  if [ -d "$RALPH_HOOKS_DIR" ]; then
    find "$RALPH_HOOKS_DIR" -name "*.sh" ! -perm -u+x -exec chmod +x {} \; 2>/dev/null
  fi
fi

# ---------------------------------------------------------------------------
# 9. Register daily cleanup cron job
# ---------------------------------------------------------------------------

CLEANUP_SCRIPT="${SCRIPTS_DIR}/cleanup.sh"
CLEANUP_TAG="# keypal:cleanup"
if [ -f "$CLEANUP_SCRIPT" ]; then
  CRONTAB_CONTENT=$(crontab -l 2>/dev/null || true)
  if ! echo "$CRONTAB_CONTENT" | grep -q "$CLEANUP_TAG"; then
    (echo "$CRONTAB_CONTENT"; echo "0 3 * * * ${CLEANUP_SCRIPT} ${CLEANUP_TAG}") | crontab -
    log_fix "Registered daily cleanup cron job (3:00 AM)"
  fi
fi

# ---------------------------------------------------------------------------
# 10. Check dependencies
# ---------------------------------------------------------------------------

command -v jq >/dev/null 2>&1 || log_error "jq is not installed"
command -v git >/dev/null 2>&1 || log_error "git is not installed"

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

if [ ${#FIXES[@]} -gt 0 ]; then
  FIXES_JSON=$(printf '%s\n' "${FIXES[@]}" | jq -R . | jq -s '.')
else
  FIXES_JSON='[]'
fi

if [ ${#ERRORS[@]} -gt 0 ]; then
  ERRORS_JSON=$(printf '%s\n' "${ERRORS[@]}" | jq -R . | jq -s '.')
else
  ERRORS_JSON='[]'
fi

jq -n \
  --argjson fixes "$FIXES_JSON" \
  --argjson errors "$ERRORS_JSON" \
  --arg status "$([ ${#ERRORS[@]} -eq 0 ] && echo "ok" || echo "error")" \
  '{status: $status, fixes_applied: $fixes, errors: $errors}'

[ ${#ERRORS[@]} -eq 0 ] && exit 0 || exit 1
