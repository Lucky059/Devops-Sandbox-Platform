#!/usr/bin/env bash
# create_env.sh — spin up a new isolated environment
set -euo pipefail

# ── Args ─────────────────────────────────────────────────
NAME="${1:-}"
TTL="${2:-1800}"   # default 30 minutes

if [[ -z "$NAME" ]]; then
    echo "Usage: ./platform/create_env.sh <name> [ttl_seconds]"
    exit 1
fi

# ── Generate unique ID ────────────────────────────────────
ENV_ID="env-$(cat /proc/sys/kernel/random/uuid | tr -d '-' | head -c 8)"
NETWORK_NAME="net-${ENV_ID}"
CONTAINER_NAME="app-${ENV_ID}"
APP_PORT=3000
CREATED_AT=$(date -u +%s)
EXPIRES_AT=$((CREATED_AT + TTL))
STATE_FILE="envs/${ENV_ID}.json"
LOG_DIR="logs/${ENV_ID}"

echo ""
echo "🚀 Creating environment: $NAME"
echo "   ID:      $ENV_ID"
echo "   TTL:     ${TTL}s"
echo ""

# ── Create log directory ──────────────────────────────────
mkdir -p "$LOG_DIR"

# ── Create dedicated Docker network ──────────────────────
echo "  → Creating Docker network: $NETWORK_NAME"
docker network create "$NETWORK_NAME" > /dev/null

# ── Connect Nginx container to new network ────────────────
echo "  → Connecting Nginx to network"
docker network connect "$NETWORK_NAME" sandbox-nginx 2>/dev/null || true

# ── Start app container ───────────────────────────────────
echo "  → Starting app container: $CONTAINER_NAME"
docker run -d \
    --name "$CONTAINER_NAME" \
    --network "$NETWORK_NAME" \
    --label "sandbox.env=$ENV_ID" \
    --label "sandbox.name=$NAME" \
    -e ENV_ID="$ENV_ID" \
    -e ENV_NAME="$NAME" \
    sandbox-demo-app:latest > /dev/null

# ── Start log shipping ────────────────────────────────────
echo "  → Starting log shipping"
docker logs -f "$CONTAINER_NAME" >> "$LOG_DIR/app.log" 2>&1 &
LOG_PID=$!
echo "$LOG_PID" > "$LOG_DIR/log_shipper.pid"

# ── Generate Nginx config ─────────────────────────────────
echo "  → Registering Nginx route: /$ENV_ID"
cat > "nginx/conf.d/${ENV_ID}.conf" << NGINX
location /${ENV_ID}/ {
    proxy_pass http://${CONTAINER_NAME}:${APP_PORT}/;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Env-ID ${ENV_ID};
    proxy_read_timeout 30s;
}
NGINX

# ── Reload Nginx ──────────────────────────────────────────
docker exec sandbox-nginx nginx -s reload > /dev/null 2>&1
echo "  → Nginx reloaded"

# ── Write state file atomically ───────────────────────────
TMP_STATE=$(mktemp)
cat > "$TMP_STATE" << JSON
{
    "id":           "$ENV_ID",
    "name":         "$NAME",
    "container":    "$CONTAINER_NAME",
    "network":      "$NETWORK_NAME",
    "created_at":   $CREATED_AT,
    "expires_at":   $EXPIRES_AT,
    "ttl":          $TTL,
    "status":       "running",
    "log_dir":      "$LOG_DIR",
    "log_pid":      $LOG_PID
}
JSON
mv "$TMP_STATE" "$STATE_FILE"
echo "  → State saved to $STATE_FILE"

# ── Done ──────────────────────────────────────────────────
echo ""
echo "✅ Environment ready!"
echo "   URL:     http://localhost/${ENV_ID}/"
echo "   ID:      $ENV_ID"
echo "   Expires: $(date -u -d @$EXPIRES_AT '+%Y-%m-%d %H:%M:%S UTC' 2>/dev/null || date -u -r $EXPIRES_AT '+%Y-%m-%d %H:%M:%S UTC')"
echo "   Logs:    make logs ENV=$ENV_ID"
echo ""
