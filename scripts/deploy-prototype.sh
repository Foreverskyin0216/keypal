#!/usr/bin/env bash
#
# deploy-prototype.sh — Deploy a prototype app and register it
#
# Usage:
#   deploy-prototype.sh <name> <dir> [port] [command]
#
# Arguments:
#   name      Service name (e.g. "todo-app")
#   dir       Project directory (e.g. ~/prototypes/todo-app)
#   port      Port to serve on (default: auto-assign from 3001-3099)
#   command   Start command (default: auto-detect)
#
# Output: JSON with status, name, port, url, pid
#

set -euo pipefail

NAME="${1:?Usage: deploy-prototype.sh <name> <dir> [port] [command]}"
DIR="${2:?Usage: deploy-prototype.sh <name> <dir> [port] [command]}"
PORT="${3:-}"
CMD="${4:-}"

REGISTRY="${HOME}/prototypes/registry.json"
LOG_DIR="${HOME}/prototypes/logs"

result() {
  jq -n \
    --arg status "$1" \
    --arg name "$NAME" \
    --arg message "$2" \
    --arg port "${3:-}" \
    --arg pid "${4:-}" \
    --arg url "${5:-}" \
    --arg dir "$DIR" \
    '{status: $status, name: $name, message: $message, port: $port, pid: $pid, url: $url, dir: $dir}'
  [ "$1" = "ok" ] && exit 0 || exit 1
}

# Ensure directories exist
mkdir -p "$(dirname "$REGISTRY")" "$LOG_DIR"
[ -f "$REGISTRY" ] || echo '{}' > "$REGISTRY"

# Resolve dir to absolute path
DIR="$(cd "$DIR" && pwd)"

# Check if already running
EXISTING_PID=$(jq -r --arg n "$NAME" '.[$n].pid // empty' "$REGISTRY")
if [ -n "$EXISTING_PID" ] && kill -0 "$EXISTING_PID" 2>/dev/null; then
  EXISTING_PORT=$(jq -r --arg n "$NAME" '.[$n].port' "$REGISTRY")
  result "ok" "Already running" "$EXISTING_PORT" "$EXISTING_PID" "http://localhost:${EXISTING_PORT}"
fi

# Auto-assign port if not specified
if [ -z "$PORT" ]; then
  USED_PORTS=$(jq -r '[.[].port] | sort | .[]' "$REGISTRY" 2>/dev/null)
  for p in $(seq 3001 3099); do
    if ! echo "$USED_PORTS" | grep -q "^${p}$" && ! lsof -iTCP:"$p" -sTCP:LISTEN >/dev/null 2>&1; then
      PORT="$p"
      break
    fi
  done
  [ -n "$PORT" ] || result "error" "No available port in 3001-3099"
fi

# Auto-detect start command if not specified
if [ -z "$CMD" ]; then
  if [ -f "$DIR/package.json" ]; then
    # Node.js project
    if grep -q '"start"' "$DIR/package.json" 2>/dev/null; then
      CMD="npm start"
    elif [ -f "$DIR/index.js" ]; then
      CMD="node index.js"
    elif [ -f "$DIR/server.js" ]; then
      CMD="node server.js"
    elif [ -f "$DIR/app.js" ]; then
      CMD="node app.js"
    else
      CMD="npx serve -s . -l $PORT"
    fi
  elif [ -f "$DIR/requirements.txt" ] || [ -f "$DIR/pyproject.toml" ]; then
    # Python project
    if [ -f "$DIR/app.py" ]; then
      CMD="python3 app.py"
    elif [ -f "$DIR/main.py" ]; then
      CMD="python3 main.py"
    elif [ -f "$DIR/manage.py" ]; then
      CMD="python3 manage.py runserver 0.0.0.0:$PORT"
    else
      CMD="python3 -m http.server $PORT"
    fi
  elif [ -f "$DIR/index.html" ]; then
    # Static site
    CMD="python3 -m http.server $PORT"
  else
    result "error" "Cannot auto-detect start command. Specify one explicitly."
  fi
fi

# Set PORT env var for frameworks that read it
export PORT

# Start the process via service-monitor (auto-repair on crash)
MONITOR_SCRIPT="${HOME}/.claude/scripts/service-monitor.sh"
LOG_FILE="${LOG_DIR}/${NAME}.log"

if [ -x "$MONITOR_SCRIPT" ]; then
  nohup "$MONITOR_SCRIPT" "$NAME" "$DIR" "$PORT" "$CMD" > /dev/null 2>&1 &
else
  cd "$DIR"
  nohup env PORT="$PORT" bash -c "$CMD" > "$LOG_FILE" 2>&1 &
fi
PID=$!

# Wait a moment and check if process is alive
sleep 1
if ! kill -0 "$PID" 2>/dev/null; then
  LAST_LOG=$(tail -5 "$LOG_FILE" 2>/dev/null || echo "no logs")
  result "error" "Process died immediately. Logs: $LAST_LOG"
fi

# Register in registry
UPDATED=$(jq --arg n "$NAME" --arg p "$PORT" --arg pid "$PID" --arg dir "$DIR" --arg cmd "$CMD" '
  .[$n] = {port: ($p | tonumber), dir: $dir, pid: ($pid | tonumber), command: $cmd, status: "running", started_at: (now | todate)}
' "$REGISTRY")
echo "$UPDATED" > "$REGISTRY"

result "ok" "Deployed successfully" "$PORT" "$PID" "http://localhost:${PORT}"
