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
PORT_MIN="${KEYPAL_PORT_MIN:-3001}"
PORT_MAX="${KEYPAL_PORT_MAX:-3099}"

if [ -z "$PORT" ]; then
  USED_PORTS=$(jq -r '[.[].port] | sort | .[]' "$REGISTRY" 2>/dev/null)
  for p in $(seq "$PORT_MIN" "$PORT_MAX"); do
    if ! echo "$USED_PORTS" | grep -q "^${p}$" && ! lsof -iTCP:"$p" -sTCP:LISTEN >/dev/null 2>&1; then
      PORT="$p"
      break
    fi
  done
  [ -n "$PORT" ] || result "error" "No available port in ${PORT_MIN}-${PORT_MAX}"
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

# Use PUBLIC_DOMAIN env var if set, otherwise resolve public IP
if [ -n "${PUBLIC_DOMAIN:-}" ]; then
  HOST="$PUBLIC_DOMAIN"
else
  HOST=$(curl -sf -m 2 http://169.254.169.254/opc/v1/vnics/ 2>/dev/null | jq -r '.[0].publicIp // empty' 2>/dev/null)
  [ -z "$HOST" ] && HOST=$(curl -sf -m 2 ifconfig.me 2>/dev/null)
  [ -z "$HOST" ] && HOST="localhost"
fi

# Add nginx reverse proxy location if nginx is running
NGINX_PROTO_DIR="/etc/nginx/conf.d/prototypes"
if [ -d "$NGINX_PROTO_DIR" ] && command -v nginx >/dev/null 2>&1; then
  cat > "${NGINX_PROTO_DIR}/${NAME}.conf" <<NGINX_LOC
location /${NAME}/ {
    proxy_pass http://127.0.0.1:${PORT}/;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
}
NGINX_LOC
  nginx -t -q 2>/dev/null && sudo systemctl reload nginx 2>/dev/null || true
  PROTO="https"
  URL="${PROTO}://${HOST}/${NAME}/"
else
  URL="http://${HOST}:${PORT}"
fi

result "ok" "Deployed successfully" "$PORT" "$PID" "$URL"
