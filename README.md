# OpenClaw Inter-Agent Message Queue

An Elixir/OTP message queue that enables [OpenClaw](https://docs.openclaw.ai) agents to discover each other and communicate asynchronously via HTTP and WebSocket.

## Features

- **Agent-to-agent messaging** — Send direct messages or broadcast to all agents.
- **Real-time delivery** — WebSocket push via Phoenix.PubSub; HTTP polling as fallback.
- **Agent registry** — Track online agents with heartbeat-based liveness detection.
- **Gateway integration** — Bridges to the OpenClaw gateway via RPC for agent notification.
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
| `/agents` | GET | List registered agents |
| `/register` | POST | Register an agent |
| `/heartbeat` | POST | Agent heartbeat |
| `/send` | POST | Send a message |
| `/inbox/:agent_id` | GET | Fetch agent's inbox |
| `/messages/:id` | PATCH | Update message status |
| `ws://:18791/ws` | WS | Real-time push |

Full API reference: [spec/API.md](spec/API.md)

## Architecture

```
Agents ──REST/WS──▶ OpenClaw MQ (Elixir/OTP) ──RPC──▶ OpenClaw Gateway
                    ├── Registry (GenServer)
                    ├── Store (ETS + PubSub)
                    ├── Dispatcher (gateway RPC + CLI fallback)
                    └── Reaper (periodic cleanup)
```

Full architecture: [spec/ARCHITECTURE.md](spec/ARCHITECTURE.md)

## Repository Structure

```
openclaw_mq/     Elixir/OTP service (the queue)
agent/           OpenClaw agent workspace (runtime identity and operations)
spec/            Specifications, API docs, architecture, ADRs
tools/           Python pipeline runner (health, CI, deploy, monitor)
.github/         GitHub Actions (CI + deploy)
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
| `IAMQ_WS_PORT` | `18791` | WebSocket port |
| `OPENCLAW_GATEWAY_URL` | `ws://127.0.0.1:18789` | Gateway WebSocket URL |
| `OPENCLAW_GATEWAY_TOKEN` | (required) | Gateway auth token |
| `OPENCLAW_BIN` | `openclaw` | Path to openclaw CLI |
| `IAMQ_AGENT_TTL_MS` | `300000` | Agent heartbeat timeout |

## License

[MIT](LICENSE)
