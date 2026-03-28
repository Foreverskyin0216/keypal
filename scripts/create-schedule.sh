#!/usr/bin/env bash
#
# create-schedule.sh — Create a scheduled task via crontab
#
# Usage:
#   create-schedule.sh <name> <cron-expr> <script-path> [description]
#
# Arguments:
#   name          Task name (e.g. "check-pr")
#   cron-expr     Cron expression (e.g. "0 9 * * *" for daily 9am)
#   script-path   Path to the script to execute
#   description   Optional human-readable description of what the task does
#
# Output: JSON with status and details
#

set -euo pipefail

NAME="${1:?Usage: create-schedule.sh <name> <cron-expr> <script-path> [description]}"
CRON="${2:?Usage: create-schedule.sh <name> <cron-expr> <script-path> [description]}"
SCRIPT="${3:?Usage: create-schedule.sh <name> <cron-expr> <script-path> [description]}"
DESC="${4:-}"

REGISTRY="${HOME}/schedules/registry.json"
LOG_DIR="${HOME}/schedules/logs"
CRON_TAG="# keypal:${NAME}"

result() {
  jq -n \
    --arg status "$1" \
    --arg name "$NAME" \
    --arg message "$2" \
    --arg cron "$CRON" \
    --arg script "$SCRIPT" \
    --arg description "$DESC" \
    '{status: $status, name: $name, message: $message, cron: $cron, script: $script, description: $description}'
  [ "$1" = "ok" ] && exit 0 || exit 1
}

# Ensure directories
mkdir -p "$(dirname "$REGISTRY")" "$LOG_DIR"
[ -f "$REGISTRY" ] || echo '{}' > "$REGISTRY"

# Resolve script to absolute path
SCRIPT="$(cd "$(dirname "$SCRIPT")" && pwd)/$(basename "$SCRIPT")"

# Ensure script exists and is executable
[ -f "$SCRIPT" ] || result "error" "Script not found: $SCRIPT"
chmod +x "$SCRIPT"

# Check if name already exists
EXISTS=$(jq -r --arg n "$NAME" '.[$n] // null' "$REGISTRY")
if [ "$EXISTS" != "null" ]; then
  result "error" "Schedule '$NAME' already exists. Use update-schedule.sh to modify."
fi

# Add to crontab
LOG_FILE="${LOG_DIR}/${NAME}.log"
CRON_LINE="${CRON} ${SCRIPT} >> ${LOG_FILE} 2>&1 ${CRON_TAG}"

# Append to crontab (preserve existing entries)
(crontab -l 2>/dev/null || true; echo "$CRON_LINE") | crontab -

# Register in registry
UPDATED=$(jq --arg n "$NAME" --arg c "$CRON" --arg s "$SCRIPT" --arg d "$DESC" '
  .[$n] = {cron: $c, script: $s, description: $d, status: "active", created_at: (now | todate)}
' "$REGISTRY")
echo "$UPDATED" > "$REGISTRY"

result "ok" "Schedule '$NAME' created (${CRON})" "$CRON" "$SCRIPT"
