#!/usr/bin/env python3
"""
poller.py — Health monitor for all active environments.
All config loaded from .env file — nothing hardcoded.
"""

import os
import json
import time
import glob
import urllib.request
import urllib.error
from datetime import datetime, timezone
from pathlib import Path

# ── Load .env if it exists ────────────────────────────────
env_file = Path(".env")
if env_file.exists():
    for line in env_file.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            key, _, value = line.partition("=")
            os.environ.setdefault(key.strip(), value.strip())

# ── Config from environment variables ────────────────────
ENVS_DIR          = "envs"
LOGS_DIR          = "logs"
POLL_INTERVAL     = int(os.getenv("HEALTH_POLL_INTERVAL",    "30"))
FAILURE_THRESHOLD = int(os.getenv("HEALTH_FAILURE_THRESHOLD", "3"))
NGINX_PORT        = os.getenv("NGINX_PORT", "80")

# Track consecutive failures per env
failure_counts = {}


def log(msg):
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    print(f"[{ts}] {msg}", flush=True)


def load_envs():
    envs = []
    for path in glob.glob(os.path.join(ENVS_DIR, "*.json")):
        try:
            with open(path) as f:
                envs.append((path, json.load(f)))
        except Exception:
            continue
    return envs


def update_status(state_path, status):
    try:
        with open(state_path) as f:
            state = json.load(f)
        state["status"] = status
        tmp = state_path + ".tmp"
        with open(tmp, "w") as f:
            json.dump(state, f, indent=4)
        os.replace(tmp, state_path)
    except Exception as e:
        log(f"⚠️  Could not update status: {e}")


def poll_env(state_path, state):
    env_id   = state["id"]
    log_file = os.path.join(LOGS_DIR, env_id, "health.log")
    os.makedirs(os.path.dirname(log_file), exist_ok=True)

    url = f"http://localhost:{NGINX_PORT}/{env_id}/health"

    start = time.time()
    try:
        req = urllib.request.urlopen(url, timeout=5)
        status_code = req.getcode()
        latency = round((time.time() - start) * 1000)
        http_status = str(status_code)
        failure_counts[env_id] = 0

        if state.get("status") == "degraded":
            update_status(state_path, "running")
            log(f"✅ {env_id} recovered — back to running")

    except Exception as e:
        latency = round((time.time() - start) * 1000)
        http_status = "FAIL"
        failure_counts[env_id] = failure_counts.get(env_id, 0) + 1
        count = failure_counts[env_id]

        log(f"⚠️  {env_id} health check failed ({count}/{FAILURE_THRESHOLD}): {e}")

        if count >= FAILURE_THRESHOLD:
            update_status(state_path, "degraded")
            log(f"🔴 {env_id} marked as DEGRADED after {count} consecutive failures")

    ts = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    with open(log_file, "a") as f:
        f.write(f"{ts} | {http_status} | {latency}ms\n")


def main():
    log("🏥 Health monitor started")
    log(f"   Polling every {POLL_INTERVAL}s")
    log(f"   Degraded after {FAILURE_THRESHOLD} consecutive failures")
    log(f"   Nginx port: {NGINX_PORT}")

    while True:
        envs = load_envs()
        if not envs:
            log("   No active environments to monitor")
        else:
            log(f"   Checking {len(envs)} environment(s)...")
            for state_path, state in envs:
                try:
                    poll_env(state_path, state)
                except Exception as e:
                    log(f"❌ Error polling {state.get('id', '?')}: {e}")

        time.sleep(POLL_INTERVAL)


if __name__ == "__main__":
    main()