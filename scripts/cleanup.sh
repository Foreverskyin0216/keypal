#!/usr/bin/env bash
#
# cleanup.sh — Clean up old uploads and rotate logs
#
# Usage:
#   cleanup.sh [--uploads-ttl-days N] [--log-max-size-mb N]
#
# Defaults:
#   --uploads-ttl-days 7     Delete uploads older than 7 days
#   --log-max-size-mb 10     Truncate logs larger than 10MB
#
# Output: JSON summary
#

set -euo pipefail

UPLOADS_TTL_DAYS=7
LOG_MAX_SIZE_MB=10

while [[ $# -gt 0 ]]; do
  case "$1" in
    --uploads-ttl-days) UPLOADS_TTL_DAYS="$2"; shift 2 ;;
    --log-max-size-mb) LOG_MAX_SIZE_MB="$2"; shift 2 ;;
    *) shift ;;
  esac
done

LOG_MAX_BYTES=$((LOG_MAX_SIZE_MB * 1024 * 1024))
UPLOADS_DIR="${HOME}/uploads"
LOG_DIRS=(
  "${HOME}/prototypes/logs"
  "${HOME}/schedules/logs"
  "${HOME}/logs/keypal"
)

uploads_deleted=0
logs_rotated=0

# ---------------------------------------------------------------------------
# 1. Clean old uploads
# ---------------------------------------------------------------------------

if [ -d "$UPLOADS_DIR" ]; then
  while IFS= read -r -d '' file; do
    rm -f "$file"
    uploads_deleted=$((uploads_deleted + 1))
  done < <(find "$UPLOADS_DIR" -type f -mtime +"$UPLOADS_TTL_DAYS" -print0 2>/dev/null)
fi

# ---------------------------------------------------------------------------
# 2. Rotate oversized logs (truncate, keeping last 1000 lines)
# ---------------------------------------------------------------------------

for log_dir in "${LOG_DIRS[@]}"; do
  [ -d "$log_dir" ] || continue
  for log_file in "$log_dir"/*.log; do
    [ -f "$log_file" ] || continue
    file_size=$(stat -f%z "$log_file" 2>/dev/null || stat -c%s "$log_file" 2>/dev/null || echo 0)
    if [ "$file_size" -gt "$LOG_MAX_BYTES" ]; then
      tail -n 1000 "$log_file" > "${log_file}.tmp"
      mv "${log_file}.tmp" "$log_file"
      logs_rotated=$((logs_rotated + 1))
    fi
  done
done

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

jq -n \
  --argjson uploads_deleted "$uploads_deleted" \
  --argjson logs_rotated "$logs_rotated" \
  --arg uploads_ttl "${UPLOADS_TTL_DAYS} days" \
  --arg log_max_size "${LOG_MAX_SIZE_MB} MB" \
  '{status: "ok", uploads_deleted: $uploads_deleted, logs_rotated: $logs_rotated, uploads_ttl: $uploads_ttl, log_max_size: $log_max_size}'
