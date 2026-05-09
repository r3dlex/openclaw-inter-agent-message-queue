<p align="center">
  <img src="assets/banner.svg" alt="openclaw-inter-agent-message-queue" width="600">
</p>

# OpenClaw Inter-Agent Message Queue (IAMQ)

The backbone communication service for every [OpenClaw](https://docs.openclaw.ai) installation. An Elixir/OTP message queue that enables agents to discover each other and communicate asynchronously via HTTP and WebSocket. This is a backbone service — not an agent — and has no IAMQ ID of its own.

## Features

- **Agent-to-agent messaging** — direct messages or broadcast to all agents
- **Tiered delivery** — WebSocket push, HTTP callbacks, CLI fallback, passive inbox polling
- **Agent discovery** — agents register with metadata and discover peers via `GET /agents`
- **Disk persistence** — messages survive restarts; stored as JSON in `queue/`
- **Cron scheduling** — agents register recurring tasks; IAMQ delivers `cron::<name>` messages at scheduled times
- **Self-healing** — OTP supervision restarts failed components; Reaper cleans up stale data
- **Sidecar client** — reusable Elixir sidecar image for agent IAMQ registration

## Skills

| Skill | Description |
|-------|-------------|
| `queue_health_check` | Checks IAMQ queue depth, agent registry, and delivery lag; reports anomalies |

Skills are stored in `skills/` and auto-improve via post-execution hooks and nightly batch processing. Workspace-level skills (`iamq_message_send`, `log_learning`, `improve_skill`) are available via the shared `../skills` volume.

## Architecture

- **Language**: Elixir/OTP
- **IAMQ ID**: N/A (backbone service, not an agent)
- **Runtime**: Docker
- **Ports**: `18790` (HTTP API), `18793` (WebSocket)

```
Agents ──REST/WS──▶ OpenClaw MQ (Elixir/OTP) ──callback/RPC──▶ Agents / Gateway
                    ├── Registry (GenServer + metadata persistence)
                    ├── Store (ETS + PubSub + disk persistence)
                    ├── Dispatcher (HTTP callback, gateway RPC, CLI fallback)
                    └── Reaper (periodic cleanup)
```

## Setup

```bash
cp .env.example .env
make build
make up
curl http://127.0.0.1:18790/status
```

## Volume Mounts

| Mount | Purpose |
|-------|---------|
| `../skills-cli:/skills-cli:ro` | Shared skills CLI tooling |
| `../skills:/workspace/skills:rw` | Workspace-level shared skills |
| `./skills:/agent/skills:rw` | Agent-specific skills |

`EMBEDDINGS_URL=http://host.docker.internal:18795` is set automatically.

## API Overview

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/status` | GET | Queue health summary |
| `/agents` | GET | List all agents (discovery) |
| `/register` | POST | Register an agent |
| `/heartbeat` | POST | Agent heartbeat |
| `/send` | POST | Send a message |
| `/inbox/:agent_id` | GET | Fetch agent's inbox |
| `/messages/:id` | PATCH | Update message status |
| `/callback` | POST/DELETE | Manage HTTP push callbacks |
| `ws://:18793/ws` | WS | Real-time push |
| `/crons` | POST/GET | Manage cron schedules |

Full reference: [spec/API.md](spec/API.md)

## Sidecar Client

Agents use `IamqSidecar.MqClient` (in `sidecar/`) to interact with the queue without raw HTTP calls. Add to `mix.exs`:

```elixir
{:iamq_sidecar, path: "../openclaw-inter-agent-message-queue/sidecar"}
```

## Links

- [spec/API.md](spec/API.md) — Full HTTP + WebSocket API reference
- [spec/ARCHITECTURE.md](spec/ARCHITECTURE.md) — OTP supervision tree
- [spec/CRON.md](spec/CRON.md) — Cron scheduling reference

## License

[MIT](LICENSE)
