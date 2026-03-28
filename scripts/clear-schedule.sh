#!/usr/bin/env bash
#
# clear-schedule.sh — Remove a scheduled task (crontab entry + files)
#
# Usage:
#   clear-schedule.sh <name>
#   clear-schedule.sh --all
#
# Output: JSON with status
#

set -euo pipefail

TARGET="${1:?Usage: clear-schedule.sh <name> | clear-schedule.sh --all}"
REGISTRY="${HOME}/schedules/registry.json"
LOG_DIR="${HOME}/schedules/logs"
TASK_DIR="${HOME}/schedules"

result() {
  jq -n --arg status "$1" --arg name "$TARGET" --arg message "$2" \
    '{status: $status, name: $name, message: $message}'
  [ "$1" = "ok" ] && exit 0 || exit 1
}

[ -f "$REGISTRY" ] || result "error" "No registry found"

if [ "$TARGET" = "--all" ]; then
  COUNT=$(jq 'length' "$REGISTRY")

  # Remove user-defined keypal crontab entries (preserve system ones like cleanup)
  CRONTAB_CONTENT=$(crontab -l 2>/dev/null || true)
  echo "$CRONTAB_CONTENT" | grep -v "# keypal:" | grep -v "^$" > /tmp/crontab_clean 2>/dev/null || true
  # Re-add system cron jobs
  echo "$CRONTAB_CONTENT" | grep "# keypal:cleanup" >> /tmp/crontab_clean 2>/dev/null || true
  # (healthcheck cron removed — monitoring is now immediate)
  crontab /tmp/crontab_clean 2>/dev/null || true
  rm -f /tmp/crontab_clean

  # Delete task directories
  jq -r 'to_entries[] | "\(.key)\t\(.value.script)"' "$REGISTRY" | \
  while IFS=$'\t' read -r name script; do
    TASK_SUBDIR="${TASK_DIR}/${name}"
    [ -d "$TASK_SUBDIR" ] && rm -rf "$TASK_SUBDIR"
  done

  # Reset registry and logs
  echo '{}' > "$REGISTRY"
  rm -rf "$LOG_DIR"
  mkdir -p "$LOG_DIR"

  jq -n --arg status "ok" --arg name "--all" --arg message "Cleared all ${COUNT} schedules" \
    '{status: $status, name: $name, message: $message}'
  exit 0
fi

# Single schedule
EXISTS=$(jq -r --arg n "$TARGET" '.[$n] // null' "$REGISTRY")
[ "$EXISTS" != "null" ] || result "error" "Schedule '$TARGET' not found"

# Remove crontab entry
CRON_TAG="# keypal:${TARGET}"
CRONTAB_CONTENT=$(crontab -l 2>/dev/null || true)
echo "$CRONTAB_CONTENT" | grep -v "$CRON_TAG" | crontab - 2>/dev/null || true

# Delete task directory
TASK_SUBDIR="${TASK_DIR}/${TARGET}"
[ -d "$TASK_SUBDIR" ] && rm -rf "$TASK_SUBDIR"

# Remove log
rm -f "${LOG_DIR}/${TARGET}.log"

# Remove from registry
UPDATED=$(jq --arg n "$TARGET" 'del(.[$n])' "$REGISTRY")
echo "$UPDATED" > "$REGISTRY"

result "ok" "Cleared schedule '$TARGET'"
