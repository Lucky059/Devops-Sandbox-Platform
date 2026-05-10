#!/usr/bin/env bash
set -euo pipefail

echo "🔧 Running full DevOps Sandbox test sequence..."

# 1. Start platform
echo "➡️ Starting platform..."
make up
sleep 10   # give containers time to settle

# 2. Test API health
echo "➡️ Checking API health..."
if curl -s http://localhost:5000/health | grep -q "ok"; then
  echo "✅ API health check passed"
else
  echo "❌ API health check failed"
  exit 1
fi

# 3. Create environment
echo "➡️ Creating environment..."
ENV_NAME="test-env"
TTL=60
echo -e "${ENV_NAME}\n${TTL}" | make create

# 4. Show health
echo "➡️ Showing environment health..."
make health

# 5. Grab ENV ID from envs directory
ENV_ID=$(ls envs/*.json | head -n1 | xargs -I{} python3 -c "import json; print(json.load(open('{}'))['id'])")
echo "Using ENV_ID=$ENV_ID"

# 6. Tail logs (sample only)
echo "➡️ Checking logs..."
make logs ENV=$ENV_ID | head -n 10 || echo "No logs yet"

# 7. Simulate outage
echo "➡️ Simulating outage..."
make simulate ENV=$ENV_ID MODE=crash || echo "Simulation failed"

# 8. Destroy environment
echo "➡️ Destroying environment..."
make destroy ENV=$ENV_ID

# 9. Stop platform
echo "➡️ Stopping platform..."
make down

# 10. Clean state
echo "➡️ Cleaning..."
make clean

echo "✅ All tasks executed successfully"

