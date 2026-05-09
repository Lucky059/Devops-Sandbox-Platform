#!/usr/bin/env bash
# cleanup_daemon.sh — auto-destroy expired environments every 60s
set -euo pipefail

LOG_FILE="logs/cleanup.log"
mkdir -p logs

log() {
    echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] $*" | tee -a "$LOG_FILE"
}

log "🔄 Cleanup daemon started (PID $$)"

while true; do
    NOW=$(date -u +%s)

    # Loop through all state files
    for STATE_FILE in envs/*.json; do
        # Skip if no files found
        [[ -e "$STATE_FILE" ]] || continue

        # Read expiry time and ID
        ENV_ID=$(python3    -c "import json; print(json.load(open('$STATE_FILE'))['id'])" 2>/dev/null || true)
        EXPIRES_AT=$(python3 -c "import json; print(json.load(open('$STATE_FILE'))['expires_at'])" 2>/dev/null || true)
        STATUS=$(python3    -c "import json; print(json.load(open('$STATE_FILE'))['status'])" 2>/dev/null || true)

        [[ -z "$ENV_ID" ]] && continue
        [[ -z "$EXPIRES_AT" ]] && continue

        # Check if expired
        if [[ "$NOW" -ge "$EXPIRES_AT" ]]; then
            log "⏰ Environment $ENV_ID has expired — destroying"
            bash platform/destroy_env.sh "$ENV_ID" >> "$LOG_FILE" 2>&1
            log "✅ Environment $ENV_ID destroyed"
        else
            REMAINING=$((EXPIRES_AT - NOW))
            log "⏳ $ENV_ID — ${REMAINING}s remaining (status: $STATUS)"
        fi
    done

    sleep 60
done
