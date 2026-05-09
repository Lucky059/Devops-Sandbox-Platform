#!/usr/bin/env bash
# simulate_outage.sh — inject failures into an environment
set -euo pipefail

ENV_ID=""
MODE=""

# ── Parse flags ───────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --env)  ENV_ID="$2"; shift 2 ;;
        --mode) MODE="$2";   shift 2 ;;
        *) echo "Unknown flag: $1"; exit 1 ;;
    esac
done

if [[ -z "$ENV_ID" || -z "$MODE" ]]; then
    echo "Usage: ./platform/simulate_outage.sh --env <env-id> --mode <crash|pause|network|recover>"
    exit 1
fi

STATE_FILE="envs/${ENV_ID}.json"
if [[ ! -f "$STATE_FILE" ]]; then
    echo "❌ Environment $ENV_ID not found"
    exit 1
fi

CONTAINER=$(python3 -c "import json; print(json.load(open('$STATE_FILE'))['container'])")
NETWORK=$(python3   -c "import json; print(json.load(open('$STATE_FILE'))['network'])")

# ── Safety guard — never simulate against platform containers ──
PROTECTED=("sandbox-nginx" "sandbox-daemon" "sandbox-api")
for PROTECTED_NAME in "${PROTECTED[@]}"; do
    if [[ "$CONTAINER" == "$PROTECTED_NAME" ]]; then
        echo "🛡️  BLOCKED: Cannot simulate outage on protected container: $CONTAINER"
        exit 1
    fi
done

echo ""
echo "💥 Simulating outage: $MODE on $ENV_ID ($CONTAINER)"

case "$MODE" in
    crash)
        docker kill "$CONTAINER"
        echo "  → Container killed (health monitor should catch within 90s)"
        ;;

    pause)
        docker pause "$CONTAINER"
        echo "  → Container paused (run recover to unpause)"
        ;;

    network)
        docker network disconnect "$NETWORK" "$CONTAINER"
        echo "  → Container disconnected from network"
        ;;

    recover)
        # Try all recovery methods
        docker unpause "$CONTAINER"      2>/dev/null && echo "  → Container unpaused" || true
        docker network connect "$NETWORK" "$CONTAINER" 2>/dev/null && echo "  → Network reconnected" || true
        docker start "$CONTAINER"        2>/dev/null && echo "  → Container started" || true
        ;;

    stress)
        docker exec "$CONTAINER" sh -c \
            "apk add --no-cache stress-ng 2>/dev/null; stress-ng --cpu 2 --timeout 30s &"
        echo "  → CPU stress started for 30s"
        ;;

    *)
        echo "❌ Unknown mode: $MODE"
        echo "   Valid modes: crash | pause | network | recover | stress"
        exit 1
        ;;
esac

echo ""
echo "✅ Outage simulation '$MODE' applied to $ENV_ID"
echo ""
