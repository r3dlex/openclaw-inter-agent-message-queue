# ADR-001: Message Queue Design

**Status**: Accepted
**Date**: 2026-03-21
**Decision makers**: Redlex Gilgamesh

## Context

OpenClaw agents need to communicate asynchronously across different channels (WhatsApp, Telegram, Discord, etc.). The gateway handles channel-to-agent routing, but there is no mechanism for **agent-to-agent** messaging, discovery, or coordination.

## Decision

Build a standalone **Inter-Agent Message Queue (IAMQ)** as an Elixir/OTP application:

1. **REST + WebSocket API** — agents can poll via HTTP or subscribe for real-time delivery via WebSocket.
2. **Agent registry** — GenServer tracking online agents with heartbeat-based liveness.
3. **ETS-backed message store** — fast in-memory storage with PubSub broadcast.
4. **Elixir/OTP** — fault-tolerant supervision, lightweight processes, built-in PubSub.
5. **Docker-first** — zero-install deployment via multi-stage build.
6. **Python pipeline runner** — operational tooling for CI, monitoring, and deployment.

## Alternatives Considered

| Option | Pros | Cons |
|--------|------|------|
| Python (FastAPI) | Lower barrier to contribution | No built-in supervision, weaker concurrency model |
| RabbitMQ/NATS | Battle-tested messaging | External dependency, overkill for initial scale |
| Gateway-embedded | No new service | Couples messaging with channel routing |

## Consequences

- **Positive**: Agents become first-class peers with discovery. OTP supervision provides self-healing. PubSub enables real-time fan-out without external dependencies.
- **Negative**: One more service to deploy. ETS loses messages on restart (acceptable for v0.1).
- **Migration path**: Add disk persistence or Redis adapter. Scale horizontally with distributed Erlang if needed.

## References

- [ARCHITECTURE.md](../ARCHITECTURE.md)
- [OpenClaw Multi-Agent Routing](https://docs.openclaw.ai/concepts/multi-agent)
