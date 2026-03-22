# CLAUDE.md — Developer Guide

This file is for **you** (Claude, Copilot, or any AI agent working on this codebase). It tells you what this project is, how it's structured, and how to work on it.

> For the OpenClaw **mq_agent** that operates this service at runtime, see `AGENTS.md`.

## What This Is

An **Elixir/OTP inter-agent message queue** for [OpenClaw](https://docs.openclaw.ai). Agents (WhatsApp, Telegram, Discord, etc.) use this service to send messages to each other asynchronously via HTTP and WebSocket.

## Quick Start

```bash
# Elixir service
cd openclaw_mq && mix deps.get && mix test && mix run --no-halt

# Python pipeline tools
python3 -m tools.pipeline_runner.cli health

# Docker (zero-install)
cp .env.example .env  # Edit with real values
make build && make up
```

## Repository Structure

```
├── AGENTS.md              # OpenClaw agent entry point (mq_agent reads this)
├── SOUL.md                # Agent identity and boundaries
├── IDENTITY.md            # Agent metadata
├── TOOLS.md               # Environment-specific notes
├── HEARTBEAT.md           # Periodic tasks
├── BOOT.md                # Startup instructions
├── openclaw_mq/           # Elixir/OTP service (the actual queue)
│   ├── lib/openclaw_mq/   # Source code
│   ├── config/            # Configuration (reads from env vars)
│   └── test/              # Elixir tests
├── queue/                 # File-based agent inboxes
│   ├── broadcast/         # Messages for all agents
│   ├── main/              # Inbox for main
│   ├── mail_agent/        # Inbox for mail_agent
│   ├── librarian_agent/   # ...
│   └── ...                # One folder per registered agent
├── spec/                  # Specifications and architecture docs
│   ├── ARCHITECTURE.md    # System design and component overview
│   ├── API.md             # Full HTTP + WebSocket API reference
│   ├── PROTOCOL.md        # Message format and field reference
│   ├── PIPELINES.md       # CI/CD and operational pipelines
│   ├── TROUBLESHOOTING.md # Common issues and fixes
│   ├── LEARNINGS.md       # Operational lessons learned
│   └── adr/               # Architecture Decision Records
├── tools/                 # Python pipeline runner
│   └── pipeline_runner/   # CLI for health, CI, deploy, monitor
├── .github/workflows/     # GitHub Actions (CI + deploy)
├── Dockerfile             # Multi-stage: Elixir release + Python tools
├── docker-compose.yml     # Local development
└── Makefile               # Developer commands
```

## Two Audiences

| Audience | Files | Purpose |
|----------|-------|---------|
| **Developers / AI agents** improving this repo | `CLAUDE.md`, `spec/`, `openclaw_mq/`, `tools/`, `.github/` | Build, test, deploy |
| **The mq_agent** operating this service | `AGENTS.md`, `SOUL.md`, `IDENTITY.md`, `TOOLS.md`, `HEARTBEAT.md`, `BOOT.md`, `queue/` | Runtime identity, monitoring, operations |

## Working on the Elixir Service

Source: `openclaw_mq/lib/openclaw_mq/`

| Module | Role |
|--------|------|
| `Application` | OTP supervisor — starts all children |
| `Registry` | GenServer tracking online agents, heartbeats, and discoverable metadata |
| `Store` | ETS-backed message storage + PubSub broadcast + disk persistence |
| `Api.Router` | HTTP REST endpoints (Plug) |
| `Api.WsHandler` | WebSocket handler (Cowboy) |
| `Gateway.Dispatcher` | Tiered delivery: HTTP callback, gateway RPC, CLI fallback, passive inbox |
| `Gateway.RpcClient` | Ephemeral WebSockex client for gateway RPC |
| `Reaper` | Periodic cleanup (stale agents, expired messages) |
| `Message` | Message struct, validation, serialization |

### Testing

```bash
cd openclaw_mq && mix test
```

### Building a Release

```bash
cd openclaw_mq && MIX_ENV=prod mix release
```

## Working on Python Tools

Source: `tools/pipeline_runner/`

These are operational pipelines — not the service itself. They check health, run CI, deploy, and monitor the Elixir service.

```bash
python3 -m tools.pipeline_runner.cli list    # Show available pipelines
python3 -m tools.pipeline_runner.cli health  # Check service health
```

## Configuration

All config is via environment variables. See `.env.example`.

**Never hardcode secrets.** The Elixir config (`openclaw_mq/config/config.exs`) reads from `System.get_env/1`. The `.env` file is gitignored.

## Key Endpoints

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
| `ws://host:18791/ws` | WS | Real-time push |

Full API: `spec/API.md`

## Architecture

See `spec/ARCHITECTURE.md` for the full system design. Key points:
- OTP supervision tree with one_for_one strategy.
- Phoenix.PubSub for real-time message fan-out.
- ETS for fast in-memory storage.
- Dispatcher uses tiered delivery: WebSocket push (PubSub), HTTP callback, passive inbox. Gateway RPC is optional.

## ADRs

Architecture decisions are in `spec/adr/`. Use [archgate](https://github.com/archgate-io/archgate-cli) or create manually.

## CI/CD

- **CI**: `.github/workflows/ci.yml` — Elixir compile + test, Python lint, Docker build.
- **Deploy**: `.github/workflows/deploy.yml` — Push to `ghcr.io` on release.
- **Pipelines**: `spec/PIPELINES.md` for full documentation.
