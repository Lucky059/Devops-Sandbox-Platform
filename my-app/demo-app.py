from flask import Flask, jsonify
import os, time

app = Flask(__name__)
START = time.time()

ENV_ID   = os.getenv("ENV_ID",   "unknown")
ENV_NAME = os.getenv("ENV_NAME", "unnamed")

@app.route("/")
@app.route("/index")
def home():
    return jsonify({
        "message":    f"Hello from environment: {ENV_NAME}",
        "env_id":     ENV_ID,
        "env_name":   ENV_NAME,
        "uptime":     int(time.time() - START)
    })

@app.route("/health")
def health():
    return jsonify({
        "status":  "ok",
        "env_id":  ENV_ID,
        "uptime":  int(time.time() - START)
    })

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=3000)
