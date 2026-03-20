# OpenClaw MQ

Elixir/OTP inter-agent message queue for OpenClaw agents.

## Ports

| Interface | Default | Env Var |
|-----------|---------|---------|
| HTTP API  | `http://127.0.0.1:18790` | `IAMQ_HTTP_PORT` |
| WebSocket | `ws://127.0.0.1:18791/ws` | `IAMQ_WS_PORT` |

## Setup

```bash
cd openclaw_mq
mix deps.get
mix compile
mix test
```

## Run

```bash
# Development (foreground)
mix run --no-halt

# Production release
MIX_ENV=prod mix release
_build/prod/rel/openclaw_mq/bin/openclaw_mq start
```

## Install as macOS LaunchAgent

```bash
# Copy and edit the example plist (adjust paths to match your system)
cp com.openclaw.mq.plist.example ~/Library/LaunchAgents/com.openclaw.mq.plist
# Edit the plist to set your release path and gateway token
launchctl load ~/Library/LaunchAgents/com.openclaw.mq.plist
```

## Configuration

All configuration is via environment variables. See `../.env.example` for the full list.

Key variables:
- `OPENCLAW_GATEWAY_URL` — Gateway WebSocket URL (default: `ws://127.0.0.1:18789`)
- `OPENCLAW_GATEWAY_TOKEN` — Authentication token for gateway RPC
- `OPENCLAW_BIN` — Path to openclaw CLI binary (default: `openclaw`)
- `IAMQ_AGENT_TTL_MS` — Agent heartbeat timeout in ms (default: `300000`)

## Quick Reference

See [spec/API.md](../spec/API.md) for the full API reference.

```bash
# Register
curl -X POST http://127.0.0.1:18790/register \
  -H 'Content-Type: application/json' \
  -d '{"agent_id": "mail_agent"}'

# Send a message
curl -X POST http://127.0.0.1:18790/send \
  -H 'Content-Type: application/json' \
  -d '{"from": "mail_agent", "to": "librarian_agent", "type": "request", "priority": "HIGH", "subject": "Research eTendering", "body": "Need a summary"}'

# Check inbox
curl http://127.0.0.1:18790/inbox/librarian_agent?status=unread

# Queue status
curl http://127.0.0.1:18790/status
```

## How Delivery Works

1. Agent A sends a message via HTTP POST or WebSocket.
2. Message is stored in ETS and published to Phoenix.PubSub.
3. If agent B has a WebSocket connection, it receives the message instantly.
4. The Dispatcher also triggers agent B via the OpenClaw gateway RPC.
5. If the gateway is down, it falls back to the `openclaw run <agent_id>` CLI.
6. The Reaper cleans up expired and old messages every 60 seconds.
