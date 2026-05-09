#!/usr/bin/env bash
# destroy_env.sh — tear down an environment cleanly
set -euo pipefail

ENV_ID="${1:-}"

if [[ -z "$ENV_ID" ]]; then
    echo "Usage: ./platform/destroy_env.sh <env-id>"
    exit 1
fi

STATE_FILE="envs/${ENV_ID}.json"

if [[ ! -f "$STATE_FILE" ]]; then
    echo "❌ Environment $ENV_ID not found (no state file)"
    exit 1
fi

# ── Read state ────────────────────────────────────────────
CONTAINER=$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d['container'])")
NETWORK=$(python3  -c "import json; d=json.load(open('$STATE_FILE')); print(d['network'])")
LOG_DIR=$(python3  -c "import json; d=json.load(open('$STATE_FILE')); print(d['log_dir'])")
LOG_PID=$(python3  -c "import json; d=json.load(open('$STATE_FILE')); print(d.get('log_pid', 0))")

echo ""
echo "🗑️  Destroying environment: $ENV_ID"

# ── Kill log shipper ──────────────────────────────────────
if [[ "$LOG_PID" -gt 0 ]]; then
    kill "$LOG_PID" 2>/dev/null || true
    echo "  → Log shipper stopped (PID $LOG_PID)"
fi

# ── Stop and remove containers with this env label ────────
echo "  → Removing containers"
docker ps -a --filter "label=sandbox.env=$ENV_ID" --format "{{.ID}}" \
    | xargs -r docker rm -f > /dev/null 2>&1 || true

# ── Disconnect and remove network ────────────────────────
echo "  → Removing network: $NETWORK"
docker network disconnect "$NETWORK" sandbox-nginx 2>/dev/null || true
docker network rm "$NETWORK" 2>/dev/null || true

# ── Remove Nginx config and reload ───────────────────────
NGINX_CONF="nginx/conf.d/${ENV_ID}.conf"
if [[ -f "$NGINX_CONF" ]]; then
    rm -f "$NGINX_CONF"
    docker exec sandbox-nginx nginx -s reload > /dev/null 2>&1 || true
    echo "  → Nginx config removed and reloaded"
fi

# ── Archive logs ──────────────────────────────────────────
if [[ -d "$LOG_DIR" ]]; then
    mkdir -p "logs/archived"
    cp -r "$LOG_DIR" "logs/archived/${ENV_ID}"
    echo "  → Logs archived to logs/archived/$ENV_ID"
fi

# ── Delete state file ─────────────────────────────────────
rm -f "$STATE_FILE"
echo "  → State file deleted"

echo ""
echo "✅ Environment $ENV_ID destroyed."
echo ""
