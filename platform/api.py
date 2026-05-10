#!/usr/bin/env python3
"""
api.py — Flask control API for DevOps Sandbox Platform
All config loaded from .env — nothing hardcoded.
"""

import os
import json
import subprocess
import glob
from datetime import datetime, timezone
from pathlib import Path
from flask import Flask, request, jsonify

# ── Load .env if it exists ────────────────────────────────
env_file = Path(".env")
if env_file.exists():
    for line in env_file.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            key, _, value = line.partition("=")
            os.environ.setdefault(key.strip(), value.strip())

# ── Config from environment variables ────────────────────
ENVS_DIR    = "envs"
LOGS_DIR    = "logs"
DEFAULT_TTL = int(os.getenv("DEFAULT_TTL", "1800"))
API_PORT    = int(os.getenv("API_PORT",    "5000"))

app = Flask(__name__)


# ── Helpers ───────────────────────────────────────────────

def load_state(env_id):
    path = os.path.join(ENVS_DIR, f"{env_id}.json")
    if not os.path.exists(path):
        return None
    with open(path) as f:
        return json.load(f)

def list_envs():
    states = []
    for path in glob.glob(os.path.join(ENVS_DIR, "*.json")):
        try:
            with open(path) as f:
                states.append(json.load(f))
        except Exception:
            continue
    return states

def ttl_remaining(state):
    now = int(datetime.now(timezone.utc).timestamp())
    return max(0, state["expires_at"] - now)

def run_script(script, *args):
    result = subprocess.run(
        ["bash", script, *args],
        capture_output=True, text=True
    )
    return result.returncode, result.stdout, result.stderr


# ── Endpoints ─────────────────────────────────────────────

@app.route("/envs", methods=["POST"])
def create_env():
    data = request.get_json(silent=True) or {}
    name = data.get("name", "unnamed")
    ttl  = str(data.get("ttl", DEFAULT_TTL))

    code, out, err = run_script("platform/create_env.sh", name, ttl)
    if code != 0:
        return jsonify({"error": err or "Failed to create environment"}), 500

    all_envs = list_envs()
    new_env  = next((e for e in all_envs if e["name"] == name), None)

    return jsonify({
        "message":       "Environment created",
        "env":           new_env,
        "ttl_remaining": ttl_remaining(new_env) if new_env else None,
        "url":           f"http://localhost/{new_env['id']}/" if new_env else None
    }), 201


@app.route("/envs", methods=["GET"])
def list_all_envs():
    envs   = list_envs()
    result = []
    for e in envs:
        result.append({
            **e,
            "ttl_remaining_seconds": ttl_remaining(e),
            "url": f"http://localhost/{e['id']}/"
        })
    return jsonify({"environments": result, "count": len(result)})


@app.route("/envs/<env_id>", methods=["DELETE"])
def destroy_env(env_id):
    if not load_state(env_id):
        return jsonify({"error": f"Environment {env_id} not found"}), 404

    code, out, err = run_script("platform/destroy_env.sh", env_id)
    if code != 0:
        return jsonify({"error": err or "Failed to destroy"}), 500

    return jsonify({"message": f"Environment {env_id} destroyed"})


@app.route("/envs/<env_id>/logs", methods=["GET"])
def get_logs(env_id):
    log_file = os.path.join(LOGS_DIR, env_id, "app.log")
    if not os.path.exists(log_file):
        log_file = os.path.join(LOGS_DIR, "archived", env_id, "app.log")
    if not os.path.exists(log_file):
        return jsonify({"error": "Log file not found"}), 404

    result = subprocess.run(["tail", "-n", "100", log_file],
                            capture_output=True, text=True)
    lines  = result.stdout.splitlines()
    return jsonify({"env_id": env_id, "lines": lines, "count": len(lines)})


@app.route("/envs/<env_id>/health", methods=["GET"])
def get_health(env_id):
    health_file = os.path.join(LOGS_DIR, env_id, "health.log")
    if not os.path.exists(health_file):
        return jsonify({"env_id": env_id, "results": [],
                        "message": "No health data yet"})

    result  = subprocess.run(["tail", "-n", "10", health_file],
                              capture_output=True, text=True)
    lines   = result.stdout.splitlines()
    results = []
    for line in lines:
        parts = line.split("|")
        if len(parts) >= 3:
            results.append({
                "timestamp": parts[0].strip(),
                "status":    parts[1].strip(),
                "latency":   parts[2].strip()
            })

    state          = load_state(env_id)
    current_status = state["status"] if state else "unknown"
    return jsonify({"env_id": env_id, "status": current_status,
                    "results": results})


@app.route("/envs/<env_id>/outage", methods=["POST"])
def simulate_outage(env_id):
    if not load_state(env_id):
        return jsonify({"error": f"Environment {env_id} not found"}), 404

    data = request.get_json(silent=True) or {}
    mode = data.get("mode", "")
    if not mode:
        return jsonify({"error": "'mode' required (crash|pause|network|recover|stress)"}), 400

    code, out, err = run_script("platform/simulate_outage.sh",
                                "--env", env_id, "--mode", mode)
    if code != 0:
        return jsonify({"error": err or "Simulation failed"}), 500

    return jsonify({"message": f"Outage '{mode}' applied to {env_id}", "output": out})


@app.route("/health", methods=["GET"])
def api_health():
    return jsonify({"status": "ok", "service": "sandbox-api"})


if __name__ == "__main__":
    os.makedirs(ENVS_DIR, exist_ok=True)
    os.makedirs(LOGS_DIR, exist_ok=True)
    app.run(host="0.0.0.0", port=API_PORT, debug=False)