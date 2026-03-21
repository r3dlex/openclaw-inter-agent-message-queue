# Learnings

Operational lessons, post-mortems, and insights captured during development and operation.

> Add entries in reverse chronological order. Each entry should capture **what happened**, **why**, and **what we changed**.

---

## 2026-03-21 — Dispatcher rewrite: tiered delivery strategy

**What happened**: Investigation revealed the gateway at `:18789` is a Node.js app that uses a challenge-response WebSocket handshake. The RPC client was connecting to the root path and immediately sending a payload, which the gateway rejected with `BadResponseError` because it expects a `connect.challenge` → `connect.auth` flow first. All three original delivery paths were broken.

**Root cause**: The gateway sends `{"type":"event","event":"connect.challenge","payload":{"nonce":"...","ts":...}}` on connection. The RPC client must respond with an auth frame including the token and nonce before sending any RPC messages. Our client skipped this entirely.

**What we changed**:
- Rewrote the Dispatcher with a tiered delivery strategy:
  1. **WebSocket push** — PubSub in `Store.put/1` handles this automatically for connected agents.
  2. **HTTP callback** — New `POST /callback` endpoint lets agents register a webhook URL. Dispatcher POSTs the full message JSON via OTP's `:httpc`.
  3. **Passive inbox** — Default fallback; agents poll `GET /inbox/:agent_id?status=unread` on heartbeat.
- Gateway WS RPC is now **opt-in** (`IAMQ_GATEWAY_RPC_ENABLED=false` by default).
- Removed `openclaw_bin` config key and CLI dispatch (commands were invalid).
- Added `:inets` and `:ssl` to `extra_applications` for `:httpc`.
- Added `POST /callback` and `DELETE /callback` endpoints to the router.

---

## 2026-03-21 — Dispatcher delivery failures (original)

**What happened**: All 3 delivery paths failed after message enqueue:
1. Gateway WebSocket RPC → `BadResponseError` (gateway process running but not accepting WS connections properly)
2. CLI fallback → `openclaw run` is not a valid command
3. Direct `sessions_send` → blocked by `tools.sessions.visibility=all` config

**What we changed**:
- Replaced `openclaw run <agent_id> --message` with `openclaw send <agent_id>` as the CLI fallback.
- Added a second fallback to `openclaw message` if `send` also fails.
- Improved error logging with truncated output to avoid log spam.

**Still open**:
- Gateway WS RPC `BadResponseError` needs investigation — likely a protocol mismatch in the RPC payload format or the gateway expects a different WebSocket handshake.
- The `tools.sessions.visibility` config may need adjusting on the gateway side.

---

## 2026-03-21 — Negative timestamp bug in Registry

**What happened**: The `/agents` API returned negative values for `registered_at` and `last_heartbeat`, making agent status unreadable.

**Why**: `System.monotonic_time(:millisecond)` returns VM-relative monotonic clock values (often negative), not wall-clock timestamps. These are correct for elapsed-time comparisons (reaping) but nonsensical as API output.

**What we changed**: Registry now stores both:
- `last_heartbeat_mono` — monotonic time, used internally by the Reaper for TTL comparisons.
- `registered_at` / `last_heartbeat` — ISO-8601 wall-clock timestamps, exposed in the API.

---

## 2026-03-21 — Architecture Decisions

**Context**: Setting up the inter-agent message queue for OpenClaw.

**Decisions made**:
- Chose Elixir/OTP for the queue service — fault-tolerant supervision, built-in PubSub, ETS for fast in-memory storage.
- Python pipeline runner for operational tooling — practical for CI/CD scripts, `gh` CLI integration, and monitoring.
- ETS (in-memory) for message storage in v0.1; persistence via disk or Redis planned for production.
- Gateway token and local paths extracted to environment variables — never hardcoded in source.
- Agent nicknames resolved at the queue level so agents can address each other informally.

**Rationale**: Elixir's OTP model is a natural fit for a message broker — processes are cheap, supervision restarts failed components, and PubSub is built-in. Python tools complement this for operational automation.

---

*Add new entries above this line.*
