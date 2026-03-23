# Testing

> How to run and extend tests for the Inter-Agent Message Queue.

## Test Suites

### Elixir — Core Queue Service

**Location:** `openclaw_mq/test/`
**Framework:** ExUnit

```bash
cd openclaw_mq && mix deps.get && mix test
```

Test categories:
- Registry (agent registration, heartbeat, reaping)
- Store (message enqueue, delivery, status transitions, ETS operations)
- API Router (HTTP endpoints, request validation, error responses)
- WebSocket handler (connection, push delivery, disconnection)
- Dispatcher (tiered delivery: callback, passive inbox, fallback)
- Reaper (stale agent cleanup, expired message purge)
- Message (struct validation, serialization)

### Elixir — Sidecar

**Location:** `sidecar/test/` (if applicable)
**Framework:** ExUnit

```bash
cd sidecar && mix deps.get && mix test
```

### Python Pipeline Runner

**Location:** `tools/pipeline_runner/`
**Framework:** pytest

```bash
python3 -m tools.pipeline_runner.cli health   # Quick health check
cd tools && poetry run pytest                  # Full test suite
```

Test categories:
- Health check pipeline (service connectivity, endpoint validation)
- CI pipeline steps (lint, compile, Docker build)
- Monitor pipeline (agent status, message throughput)

### Docker (Full Stack)

```bash
# Zero-install: build and run all tests
docker compose run --rm test
```

This compiles the Elixir release, runs ExUnit, and executes Python pipeline tests in a single container pass.

## Integration Test Flow

The canonical integration test verifies the full message lifecycle:

```
1. Register agent_a  →  POST /register
2. Register agent_b  →  POST /register
3. Send message       →  POST /send (from: agent_a, to: agent_b)
4. Poll inbox         →  GET /inbox/agent_b?status=unread
5. Verify delivery    →  Assert message present with correct fields
6. Mark read          →  PATCH /messages/:id {status: "read"}
7. Verify status      →  GET /inbox/agent_b?status=unread returns empty
```

Run manually:

```bash
# Start the service
cd openclaw_mq && mix run --no-halt &

# Register
curl -X POST http://localhost:18790/register \
  -H "Content-Type: application/json" \
  -d '{"agent_id": "test_sender", "capabilities": ["test"]}'

curl -X POST http://localhost:18790/register \
  -H "Content-Type: application/json" \
  -d '{"agent_id": "test_receiver", "capabilities": ["test"]}'

# Send
curl -X POST http://localhost:18790/send \
  -H "Content-Type: application/json" \
  -d '{"from": "test_sender", "to": "test_receiver", "type": "info", "subject": "test", "body": "hello"}'

# Poll
curl http://localhost:18790/inbox/test_receiver?status=unread
```

## CI (GitHub Actions)

**Workflow:** `.github/workflows/ci.yml`

| Job | What it runs |
|-----|-------------|
| `elixir-compile` | `mix compile --warnings-as-errors` |
| `elixir-test` | `mix test` |
| `python-lint` | Ruff lint on pipeline runner |
| `docker-build` | Build Docker image, run containerized tests |

## Adding Tests

### For a new Elixir module

1. Create `openclaw_mq/test/<module_name>_test.exs`
2. Test public API, error paths, and edge cases
3. Run: `cd openclaw_mq && mix test test/<module_name>_test.exs`

### For a new API endpoint

1. Add route in `Api.Router`
2. Add ExUnit test using `Plug.Test.conn/3` to simulate requests
3. Test success, validation errors, and not-found cases

## Related

- API reference: [API.md](API.md)
- Protocol: [PROTOCOL.md](PROTOCOL.md)
- Architecture: [ARCHITECTURE.md](ARCHITECTURE.md)
- Pipelines: [PIPELINES.md](PIPELINES.md)

---
*Owner: mq_agent*
