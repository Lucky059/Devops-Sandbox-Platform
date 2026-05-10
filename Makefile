.PHONY: up down create destroy logs health simulate clean build

# ── Start the platform ────────────────────────────────────
up:
	@echo "🚀 Starting DevOps Sandbox Platform..."
	@mkdir -p logs envs nginx/conf.d
	@touch nginx/conf.d/.gitkeep

	# Start Nginx
	docker run -d \
		--name sandbox-nginx \
		--network bridge \
		-p 80:80 \
		-v $(PWD)/nginx/nginx.conf:/etc/nginx/nginx.conf:ro \
		-v $(PWD)/nginx/conf.d:/etc/nginx/conf.d \
		nginx:latest || echo "Nginx already running"

	# Start API
	docker run -d \
		--name sandbox-api \
		--network bridge \
		-p 5000:5000 \
		-v $(PWD):/app \
		-w /app \
		-e API_PORT=5000 \
		python:3.11-alpine \
		sh -c "pip install flask -q && python platform/api.py" || echo "API already running"

	# Connect API to nginx network
	docker network connect bridge sandbox-api 2>/dev/null || true

	# Start cleanup daemon in background
	nohup bash platform/cleanup_daemon.sh > logs/cleanup.log 2>&1 &
	@echo "$$!" > logs/daemon.pid

	# Start health monitor in background
	nohup python3 monitor/poller.py > logs/monitor.log 2>&1 &
	@echo "$$!" > logs/monitor.pid
    
	@echo "⏳ Waiting for platform to stabilize..."
	@sleep 25

	@echo ""
	@echo "✅ Platform is up!"
	@echo "   API:     http://localhost:5000"
	@echo "   Nginx:   http://localhost:80"
	@echo ""

# ── Stop everything ───────────────────────────────────────
down:
	@echo "🛑 Stopping platform..."

	# Destroy all active environments first
	@for f in envs/*.json; do \
		[ -e "$$f" ] || continue; \
		ENV_ID=$$(python3 -c "import json; print(json.load(open('$$f'))['id'])"); \
		bash platform/destroy_env.sh "$$ENV_ID" 2>/dev/null || true; \
	done

	# Stop containers
	docker rm -f sandbox-nginx sandbox-api 2>/dev/null || true

	# Kill background processes
	@[ -f logs/daemon.pid ]  && kill $$(cat logs/daemon.pid)  2>/dev/null || true
	@[ -f logs/monitor.pid ] && kill $$(cat logs/monitor.pid) 2>/dev/null || true
	@rm -f logs/daemon.pid logs/monitor.pid

	@echo "✅ Platform stopped"

# ── Create a new environment ─────────────────────────────
create:
	@read -p "Environment name: " NAME; \
	read -p "TTL in seconds (default 1800): " TTL; \
	TTL=$${TTL:-1800}; \
	bash platform/create_env.sh "$$NAME" "$$TTL"

# ── Destroy a specific environment ───────────────────────
destroy:
	@[ -n "$(ENV)" ] || (echo "Usage: make destroy ENV=env-abc123" && exit 1)
	bash platform/destroy_env.sh $(ENV)

# ── Tail logs for an environment ─────────────────────────
logs:
	@[ -n "$(ENV)" ] || (echo "Usage: make logs ENV=env-abc123" && exit 1)
	@LOG_FILE="logs/$(ENV)/app.log"; \
	ARCH_FILE="logs/archived/$(ENV)/app.log"; \
	if [ -f "$$LOG_FILE" ]; then \
		tail -f "$$LOG_FILE"; \
	elif [ -f "$$ARCH_FILE" ]; then \
		tail -100 "$$ARCH_FILE"; \
	else \
		echo "No logs found for $(ENV)"; \
	fi

# ── Show health status of all environments ───────────────
health:
	@echo "── Environment Health ──────────────────────────────"
	@for f in envs/*.json; do \
		[ -e "$$f" ] || continue; \
		python3 -c "\
import json; \
d = json.load(open('$$f')); \
import time; \
remaining = max(0, d['expires_at'] - int(time.time())); \
print(f\"  {d['id']}  status={d['status']}  ttl_remaining={remaining}s  name={d['name']}\")"; \
	done
	@echo ""

# ── Simulate an outage ────────────────────────────────────
simulate:
	@[ -n "$(ENV)" ]  || (echo "Usage: make simulate ENV=env-abc123 MODE=crash" && exit 1)
	@[ -n "$(MODE)" ] || (echo "Usage: make simulate ENV=env-abc123 MODE=crash" && exit 1)
	bash platform/simulate_outage.sh --env $(ENV) --mode $(MODE)

# ── Build demo app image ──────────────────────────────────
build:
	@echo "🔨 Building demo app image..."
	docker build -t sandbox-demo-app:latest demo-app/
	@echo "✅ Image built: sandbox-demo-app:latest"

# ── Wipe all state and logs ───────────────────────────────
clean:
	@echo "🧹 Cleaning all state and logs..."
	@rm -rf envs/*.json logs/cleanup.log logs/monitor.log
	@find logs -maxdepth 1 -mindepth 1 -type d ! -name archived -exec rm -rf {} + 2>/dev/null || true
	@rm -f nginx/conf.d/*.conf
	@echo "✅ Clean complete"
