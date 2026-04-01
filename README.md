<p align="center">
  <img src="assets/banner.svg" alt="openclaw-inter-agent-message-queue" width="600">
</p>

# OpenClaw Inter-Agent Message Queue

An Elixir/OTP message queue that enables [OpenClaw](https://docs.openclaw.ai) agents to discover each other and communicate asynchronously via HTTP and WebSocket.

## Features

- **Agent-to-agent messaging** — Send direct messages or broadcast to all agents.
- **Tiered delivery** — WebSocket push, HTTP callbacks, CLI fallback, passive inbox polling.
- **Agent discovery** — Agents register with metadata (name, emoji, capabilities) and discover peers via `GET /agents`.
- **Disk persistence** — Messages survive service restarts; stored as JSON in `queue/`.
- **Agent registry** — Track online agents with heartbeat-based liveness detection and metadata persistence.
- **Self-healing** — OTP supervision restarts failed components; Reaper cleans up stale data.
- **Zero-install deployment** — Docker multi-stage build (Elixir release + Python tools).

## Quick Start

### Docker (recommended)

```bash
cp .env.example .env   # Edit with your gateway token
make build
make up
curl http://127.0.0.1:18790/status
```

### Local Development

Requires Elixir ~> 1.15 and OTP 26.

```bash
cd openclaw_mq
mix deps.get
mix test
mix run --no-halt
```

## API Overview

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/status` | GET | Queue health summary |
| `/agents` | GET | List all agents with metadata (discovery) |
| `/agents/:agent_id` | GET | Get single agent profile |
| `/agents/:agent_id` | PUT | Update agent metadata |
| `/register` | POST | Register an agent (with optional metadata) |
| `/heartbeat` | POST | Agent heartbeat |
| `/send` | POST | Send a message |
| `/inbox/:agent_id` | GET | Fetch agent's inbox |
| `/messages/:id` | PATCH | Update message status |
| `/callback` | POST | Register HTTP callback URL for push delivery |
| `/callback` | DELETE | Remove HTTP callback URL |
| `ws://:18793/ws` | WS | Real-time push |

Full API reference: [spec/API.md](spec/API.md)

## Architecture

```
Agents ──REST/WS──▶ OpenClaw MQ (Elixir/OTP) ──callback/RPC──▶ Agents / Gateway
                    ├── Registry (GenServer + metadata persistence)
                    ├── Store (ETS + PubSub + disk persistence)
                    ├── Dispatcher (HTTP callback, gateway RPC, CLI fallback)
                    └── Reaper (periodic cleanup)
```

Full architecture: [spec/ARCHITECTURE.md](spec/ARCHITECTURE.md)

## Repository Structure

```
openclaw_mq/     Elixir/OTP service (the queue)
queue/           File-based agent inboxes (one folder per agent + broadcast/)
spec/            Specifications, API docs, architecture, ADRs
tools/           Python pipeline runner (health, CI, deploy, monitor)
.github/         GitHub Actions (CI + deploy)
AGENTS.md        OpenClaw agent entry point (mq_agent reads this at runtime)
SOUL.md          Agent identity and boundaries
IDENTITY.md      Agent metadata
```

## Documentation

| Document | Description |
|----------|-------------|
| [CLAUDE.md](CLAUDE.md) | Developer/AI agent guide for working on this repo |
| [spec/ARCHITECTURE.md](spec/ARCHITECTURE.md) | System design and OTP supervision tree |
| [spec/API.md](spec/API.md) | HTTP + WebSocket API reference |
| [spec/PROTOCOL.md](spec/PROTOCOL.md) | Message format and field reference |
| [spec/PIPELINES.md](spec/PIPELINES.md) | CI/CD and operational pipelines |
| [spec/TROUBLESHOOTING.md](spec/TROUBLESHOOTING.md) | Common issues and fixes |
| [spec/LEARNINGS.md](spec/LEARNINGS.md) | Operational lessons learned |
| [spec/adr/](spec/adr/) | Architecture Decision Records |

## Pipelines

Python CLI for operational tasks:

```bash
python3 -m tools.pipeline_runner.cli health   # Check service health
python3 -m tools.pipeline_runner.cli ci       # Run full CI (Elixir + Python lint)
python3 -m tools.pipeline_runner.cli deploy   # Build and push Docker image
python3 -m tools.pipeline_runner.cli monitor  # Monitor queue and alert on anomalies
```

## Configuration

All settings via environment variables. See [.env.example](.env.example).

| Variable | Default | Purpose |
|----------|---------|---------|
| `IAMQ_HTTP_PORT` | `18790` | HTTP API port |
| `IAMQ_WS_PORT` | `18793` | WebSocket port |
| `IAMQ_AGENT_TTL_MS` | `1800000` | Agent heartbeat TTL (30 min) |
| `IAMQ_REAP_INTERVAL_MS` | `60000` | Reaper check interval (1 min) |
| `IAMQ_QUEUE_DIR` | `../../queue` | Directory for message persistence |
| `IAMQ_GATEWAY_RPC_ENABLED` | `false` | Enable gateway WS RPC delivery |
| `OPENCLAW_GATEWAY_URL` | `ws://127.0.0.1:18789` | Gateway WebSocket URL |
| `OPENCLAW_GATEWAY_TOKEN` | `""` | Gateway auth token (for RPC) |

## License

[MIT](LICENSE)
