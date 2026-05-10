# DevOps Sandbox Platform 🏗️

A self-service platform for spinning up isolated temporary environments, simulating outages, monitoring health, and auto-destroying everything when the timer runs out.

Think of it as a **mini internal Heroku** with a chaos engineering toggle.

---

## Architecture

```
         Developer
              │
     make create / API call
              │
    ┌─────────▼──────────┐
    │    Control API      │  Flask — wraps all shell scripts
    │    port 5000        │  POST /envs, DELETE /envs/:id
    └─────────┬──────────┘
              │
    ┌─────────▼──────────┐
    │       Nginx         │  Single front door — port 80
    │                     │  conf.d/*.conf auto-generated
    │  /env-abc123/ ──────┼──► app-env-abc123:3000
    │  /env-xyz789/ ──────┼──► app-env-xyz789:3000
    └────────────────────┘

    ┌────────────────────┐   ┌────────────────────┐
    │   app-env-abc123   │   │   app-env-xyz789   │
    │   net-env-abc123   │   │   net-env-xyz789   │
    │   port 3000        │   │   port 3000        │
    └────────────────────┘   └────────────────────┘

    ┌────────────────────┐
    │   Cleanup Daemon   │  Runs every 60s
    │   cleanup_daemon   │  Destroys expired envs
    └────────────────────┘

    ┌────────────────────┐
    │   Health Monitor   │  Polls /health every 30s
    │   monitor/poller   │  Marks degraded after 3 fails
    └────────────────────┘

    State:   envs/*.json
    Logs:    logs/<env-id>/app.log
             logs/<env-id>/health.log
             logs/cleanup.log
```

---

## Prerequisites

- Docker + Docker Compose
- Python 3.x
- `pip install flask requests`
- Linux (Ubuntu)

---

## Quick Start (5 commands)

```bash
# 1. Clone
git clone https://github.com/Lucky059/devops-sandbox.git
cd devops-sandbox

# 2. Build demo app image
make build

# 3. Start the platform
make up

# 4. Create your first environment
make create

# 5. Check it is running
make health
```

---

## All Commands

```bash
make up                          # start nginx, api, daemon, monitor
make down                        # stop everything, destroy all envs
make build                       # build demo app Docker image
make create                      # create new env (prompts for name + TTL)
make destroy ENV=env-abc123      # destroy specific env
make logs ENV=env-abc123         # tail app logs
make health                      # show all env health statuses
make simulate ENV=env-abc123 MODE=crash   # simulate outage
make clean                       # wipe all state and logs
```

---

## API Endpoints

| Method | Endpoint | Description |
|---|---|---|
| POST | `/envs` | Create environment |
| GET | `/envs` | List active environments |
| DELETE | `/envs/:id` | Destroy environment |
| GET | `/envs/:id/logs` | Last 100 lines of app.log |
| GET | `/envs/:id/health` | Last 10 health check results |
| POST | `/envs/:id/outage` | Trigger outage simulation |

**Examples:**
```bash
# Create via API
curl -X POST http://localhost:5000/envs \
  -H "Content-Type: application/json" \
  -d '{"name": "my-test", "ttl": 600}'

# List all
curl http://localhost:5000/envs

# Simulate crash
curl -X POST http://localhost:5000/envs/env-abc123/outage \
  -H "Content-Type: application/json" \
  -d '{"mode": "crash"}'
```

---

## Full Demo Walkthrough

```bash
# 1. Start platform
make up

# 2. Create environment
make create
# → Enter name: demo
# → Enter TTL: 300 (5 minutes)
# → URL: http://localhost/env-abc123/

# 3. Test it
curl http://localhost/env-abc123/
curl http://localhost/env-abc123/health

# 4. Check health status
make health

# 5. Simulate outage
make simulate ENV=env-abc123 MODE=crash

# 6. Watch health monitor catch it
make logs ENV=env-abc123

# 7. Recover
make simulate ENV=env-abc123 MODE=recover

# 8. Watch auto-destroy when TTL expires (or manually)
make destroy ENV=env-abc123

# 9. Generate nothing — cleanup daemon handles it automatically
```

---

## Outage Simulation Modes

| Mode | What it does |
|---|---|
| `crash` | `docker kill` the container |
| `pause` | `docker pause` — freezes the container |
| `network` | Disconnects container from network |
| `recover` | Restores whatever was broken |
| `stress` | Spikes CPU with stress-ng |

---

## Known Limitations

- Nginx must be running before creating environments
- Demo app is a simple Flask server — swap for any Docker image
- Health monitor polls via Nginx URL — if Nginx is down, all envs show as degraded
- Log shipping uses `docker logs -f` (Approach A) — no persistent log aggregator

---

## License

MIT