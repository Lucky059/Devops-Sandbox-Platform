#!/usr/bin/env bash
# cleanup_daemon.sh — auto-destroy expired environments
set -euo pipefail

# ── Load .env if it exists ────────────────────────────────
if [[ -f ".env" ]]; then
    set -a
    source .env
    set +a
fi

CLEANUP_INTERVAL="${CLEANUP_INTERVAL:-60}"
LOG_FILE="logs/cleanup.log"
mkdir -p logs

log() {
    echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] $*" | tee -a "$LOG_FILE"
}

log "🔄 Cleanup daemon started (PID $$)"
log "   Checking every ${CLEANUP_INTERVAL}s"

while true; do
    NOW=$(date -u +%s)

    for STATE_FILE in envs/*.json; do
        [[ -e "$STATE_FILE" ]] || continue

        ENV_ID=$(python3     -c "import json; print(json.load(open('$STATE_FILE'))['id'])"         2>/dev/null || true)
        EXPIRES_AT=$(python3 -c "import json; print(json.load(open('$STATE_FILE'))['expires_at'])" 2>/dev/null || true)
        STATUS=$(python3     -c "import json; print(json.load(open('$STATE_FILE'))['status'])"     2>/dev/null || true)

        [[ -z "$ENV_ID" ]]     && continue
        [[ -z "$EXPIRES_AT" ]] && continue

        if [[ "$NOW" -ge "$EXPIRES_AT" ]]; then
            log "⏰ $ENV_ID has expired — destroying"
            bash platform/destroy_env.sh "$ENV_ID" >> "$LOG_FILE" 2>&1
            log "✅ $ENV_ID destroyed"
        else
            REMAINING=$((EXPIRES_AT - NOW))
            log "⏳ $ENV_ID — ${REMAINING}s remaining (status: $STATUS)"
        fi
    done

    sleep "$CLEANUP_INTERVAL"
done