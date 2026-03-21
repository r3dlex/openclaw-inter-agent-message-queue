# Troubleshooting

Common issues and their solutions.

## Service Won't Start

**Symptom**: `make run` or `make up` fails.

1. Check Elixir is installed: `mix --version` (requires Elixir ~> 1.15).
2. Fetch deps: `cd openclaw_mq && mix deps.get`.
3. Check port conflict: `lsof -i :18790` or `lsof -i :18791`.
4. For Docker: verify Docker is running (`docker info`), then `make build && make up`.
5. Check logs: `make logs` (Docker) or `/tmp/openclaw/openclaw-mq.log` (LaunchAgent).

## Connection Refused

**Symptom**: `curl http://127.0.0.1:18790/status` fails.

1. Confirm the service is running: `curl -s http://127.0.0.1:18790/status`.
2. If Docker: check ports are exposed in `docker-compose.yml`.
3. Check `.env` for correct `IAMQ_HTTP_PORT` / `IAMQ_WS_PORT`.

## WebSocket Disconnects

**Symptom**: Agents lose WebSocket connection.

1. Register via WebSocket first: send `{"action": "register", "agent_id": "your_id"}`.
2. Send periodic heartbeats: `{"action": "heartbeat"}` (idle timeout is 5 min).
3. Check for network issues between agent and MQ service.

## Messages Not Delivered

**Symptom**: Messages queued but recipient doesn't receive them.

1. Check recipient is registered: `curl http://127.0.0.1:18790/agents`.
2. Check message status: `curl http://127.0.0.1:18790/inbox/{agent_id}?status=unread`.
3. Check if messages expired (`expiresAt` field).
4. Run monitor pipeline: `python3 -m tools.pipeline_runner.cli monitor`.
5. Check Dispatcher logs for gateway RPC / CLI fallback errors.

## Stale Agents Getting Reaped

**Symptom**: Agents disappear from registry.

1. Agents must heartbeat within 5 minutes (configurable via `IAMQ_AGENT_TTL_MS`).
2. Increase TTL if agents have long gaps between sessions.
3. WebSocket connections auto-heartbeat on `register`; HTTP agents must `POST /heartbeat` explicitly.

## Gateway RPC Failures

**Symptom**: Dispatcher logs show "Gateway RPC failed".

Gateway WS RPC is **disabled by default** (`IAMQ_GATEWAY_RPC_ENABLED=false`). The OpenClaw gateway uses a challenge-response handshake that the RPC client doesn't yet implement. If you enable it:

1. Verify `OPENCLAW_GATEWAY_URL` in `.env` (default: `ws://127.0.0.1:18789`).
2. Verify `OPENCLAW_GATEWAY_TOKEN` in `.env`.
3. Check the OpenClaw gateway is running: `openclaw status`.
4. Messages still arrive via HTTP callback (if registered) or passive inbox polling.

## HTTP Callback Failures

**Symptom**: Dispatcher logs show "HTTP callback failed".

1. Verify the agent registered a callback URL: check dispatcher logs for registration.
2. Ensure the callback URL is reachable from the MQ service host.
3. The callback must respond with HTTP 2xx within 5 seconds.
4. Messages still arrive in the passive inbox as a fallback.

## Docker Build Fails

1. Check Docker daemon is running.
2. Try: `docker compose build --no-cache`.
3. Ensure Elixir deps resolve: `cd openclaw_mq && mix deps.get`.

## Still Stuck?

1. Check the [LEARNINGS](LEARNINGS.md) doc for past issues.
2. Open an issue on GitHub with logs and reproduction steps.
