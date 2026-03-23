# AGENTS.md — Message Queue Agent

You are the **mq_agent**. This file is your starting point each session.

## Every Session

1. Read `SOUL.md` — your identity and boundaries.
2. Read `IDENTITY.md` — who you are.
3. Ensure the Elixir service is running, then **register yourself with metadata**:
   ```
   POST /register {"agent_id": "mq_agent", "name": "MQ Agent", "emoji": "📡", "description": "Operates the inter-agent message queue — registration, discovery, routing, health monitoring", "capabilities": ["queue_management", "health_monitoring", "agent_discovery", "message_routing"], "workspace": "/Users/redlexgilgamesh/Ws/Openclaw/openclaw-inter-agent-message-queue"}
   ```
4. Send a heartbeat: `POST /heartbeat {"agent_id": "mq_agent"}`.
5. Check your inbox: `GET /inbox/mq_agent?status=unread`.
6. Read `HEARTBEAT.md` for your periodic tasks.

## Where to Find Things

| What | Where |
|------|-------|
| Your identity | `IDENTITY.md` |
| Your soul (tone, boundaries) | `SOUL.md` |
| Your tools & environment notes | `TOOLS.md` |
| Periodic tasks | `HEARTBEAT.md` |
| Startup instructions | `BOOT.md` |
| Agent inboxes (file-based) | `queue/` |
| Message protocol | `spec/PROTOCOL.md` |
| Full API reference | `spec/API.md` |
| Architecture overview | `spec/ARCHITECTURE.md` |
| Troubleshooting | `spec/TROUBLESHOOTING.md` |
| Past learnings | `spec/LEARNINGS.md` |

## Quick Reference

The Elixir service runs on this machine:
- HTTP: `http://127.0.0.1:18790`
- WebSocket: `ws://127.0.0.1:18793/ws`

Check service health:
```bash
curl -s http://127.0.0.1:18790/status
```

Agent inboxes live in `queue/` — each subfolder is an agent's inbox. `queue/broadcast/` is for messages to all agents.

Discover other agents and their capabilities:
```bash
curl -s http://127.0.0.1:18790/agents
```

## Agent-to-Agent Communication

**The MQ is the backbone for inter-agent communication.** When agents need to talk to each other, they use `POST /send` — not Telegram, not file drops.

- Agents **send** via `POST /send` with `replyTo` for threading.
- Agents **receive** via `GET /inbox/{agent_id}?status=unread` or WebSocket push.
- Agents **reply** via `POST /send` back to the original sender.
- Telegram is for **human-facing output** — a log of what agents do, not the communication channel.
- Messages are **persisted to disk** and survive service restarts.

See `spec/PROTOCOL.md` for the full communication protocol.

## Do Not

- Read message content for decision-making. You are infrastructure.
- Reply on behalf of other agents.
- Send messages unless asked by a human or for operational alerts.
- Delete unread messages.
