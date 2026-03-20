# Architecture

> See also: [ADR-001](adr/001-message-queue-design.md) for foundational design decisions.

## Overview

The **OpenClaw Inter-Agent Message Queue (IAMQ)** is an Elixir/OTP service that enables OpenClaw agents to discover each other and exchange messages asynchronously. It acts as the nervous system for multi-agent deployments.

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│   Agent A    │     │   Agent B    │     │   Agent C    │
│  (WhatsApp)  │     │  (Telegram)  │     │  (Discord)   │
└──────┬───────┘     └──────┬───────┘     └──────┬───────┘
       │  REST/WS           │  REST/WS           │  REST/WS
       └────────────┬───────┴────────────┬───────┘
                    │                    │
              ┌─────▼────────────────────▼─────┐
              │     OpenClaw MQ (Elixir/OTP)   │
              │  ┌───────────┐ ┌────────────┐  │
              │  │ Registry  │ │ Store(ETS) │  │
              │  │(GenServer)│ │(GenServer) │  │
              │  └───────────┘ └────────────┘  │
              │  ┌────────┐ ┌──────────────┐   │
              │  │ Reaper │ │  Dispatcher  │   │
              │  └────────┘ └──────────────┘   │
              │  ┌───────────────────────────┐ │
              │  │     Phoenix.PubSub        │ │
              │  └───────────────────────────┘ │
              └────────────────────────────────┘
               :18790 (HTTP)    :18791 (WebSocket)
                           │
                    ┌──────▼──────┐
                    │  OpenClaw   │
                    │  Gateway    │
                    │  (:18789)   │
                    └─────────────┘
```

## OTP Supervision Tree

```
OpenclawMq.Supervisor (one_for_one)
├── Phoenix.PubSub          — Pub/sub backbone for real-time message fan-out
├── OpenclawMq.Registry     — GenServer tracking online agents + heartbeats
├── OpenclawMq.Store        — GenServer with ETS-backed message storage
├── Plug.Cowboy (HTTP)      — REST API on port 18790
├── Plug.Cowboy (WS)        — WebSocket server on port 18791
├── OpenclawMq.Gateway.Dispatcher — Async delivery via gateway RPC + CLI fallback
└── OpenclawMq.Reaper       — Periodic cleanup (stale agents, expired messages)
```

## Components

### Registry (`openclaw_mq/lib/openclaw_mq/registry.ex`)

GenServer tracking online agents:

- **Register/unregister** — agents declare themselves on session start.
- **Heartbeat** — periodic liveness signal; auto-registers unknown agents.
- **Reap** — removes agents that haven't heartbeated within the TTL (default 5 min).

### Store (`openclaw_mq/lib/openclaw_mq/store.ex`)

ETS-backed message persistence with PubSub broadcast:

- **put** — stores message, broadcasts via Phoenix.PubSub to the target topic.
- **inbox** — queries all messages for an agent (direct + broadcast), with optional status filter.
- **update_status** — transitions: `unread` → `read` → `acted` → `archived`.
- **purge_expired** / **purge_old** — cleanup for TTL and 7-day-old messages.

### WebSocket Handler (`openclaw_mq/lib/openclaw_mq/api/ws_handler.ex`)

Cowboy WebSocket handler for real-time push:

- Agents connect to `ws://host:18791/ws`.
- Actions: `register`, `heartbeat`, `send`, `ack`.
- Subscribes to PubSub topics for real-time message delivery.

### Dispatcher (`openclaw_mq/lib/openclaw_mq/gateway/dispatcher.ex`)

Async delivery to agents via the OpenClaw gateway:

- Tries gateway WebSocket RPC first (ephemeral connection via `WebSockex`).
- Falls back to `openclaw run <agent_id>` CLI if gateway is unreachable.

### Reaper (`openclaw_mq/lib/openclaw_mq/reaper.ex`)

Periodic GenServer (every 60s):

- Reaps stale agents (no heartbeat within TTL).
- Purges expired messages.
- Purges old acted/archived messages (>7 days).

### Pipeline Runner (`tools/pipeline_runner/`)

Python CLI for operational pipelines (health, CI, deploy, monitor). See [PIPELINES.md](PIPELINES.md).

## Data Flow

1. Agent registers via `POST /register` or WebSocket `{"action": "register"}`.
2. Sender posts message via `POST /send` or WebSocket `{"action": "send"}`.
3. Store persists to ETS and broadcasts via PubSub.
4. Connected WebSocket clients receive instantly.
5. Dispatcher notifies the target agent via gateway RPC (or CLI fallback).
6. Recipient fetches inbox via `GET /inbox/:agent_id` or receives via WebSocket.
7. Recipient acknowledges via `PATCH /messages/:id` or WebSocket `{"action": "ack"}`.

## Message Protocol

See [PROTOCOL.md](PROTOCOL.md) for the full message format, field reference, and examples.

## Deployment

- **Local dev**: `make run` (requires Elixir installed).
- **Docker**: `make up` (zero-install, builds Elixir release in container).
- **macOS LaunchAgent**: see `openclaw_mq/com.openclaw.mq.plist.example`.

## Security

- Gateway token via `OPENCLAW_GATEWAY_TOKEN` env var (never hardcoded).
- All secrets in `.env` (gitignored).
- No sensitive data stored in messages — agents handle encryption.
