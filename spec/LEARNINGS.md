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

## 2026-04-08 — Corrected Ed25519 device-auth protocol for IAMQ gateway RPC

**What happened**: The previous implementation plan for the IAMQ gateway RPC client contained three critical errors about the OpenClaw gateway protocol.

**Errors in previous plan**:

1. **Wrong algorithm** — Used `secp256r1` / `ecdsa` throughout. OpenClaw uses **Ed25519** via Node.js `crypto.generateKeyPairSync("ed25519")` and `crypto.sign(null, Buffer.from(payload, "utf8"), key)`.

2. **Wrong payload format** — Used `<<nonce :: binary, signedAt :: integer>>` (binary packed struct). OpenClaw's `buildDeviceAuthPayload` produces a **pipe-delimited UTF-8 string**:
   ```
   v2|deviceId|clientId|clientMode|role|scopes|signedAtMs|token|nonce
   v3|deviceId|clientId|clientMode|role|scopes|signedAtMs|token|nonce|platform|deviceFamily
   ```

3. **Wrong signature encoding** — Used `Base.encode64`. OpenClaw uses **Base64URL** (`Base.url_encode64/1` with `padding: false`, which replaces `+` → `-`, `/` → `_`, strips `=` padding).

**What we corrected**:

### Key Generation — Ed25519

```elixir
# Generate Ed25519 keypair
{public_key, private_key} = :crypto.generate_key(:ed25519)

# PEM encode
public_key_pem = public_key
  |> :public_key.pem_entry_encode(:'SubjectPublicKeyInfo')
  |> :public_key.pem_encode()

private_key_pem = private_key
  |> :public_key.pem_entry_encode(:'PrivateKeyInfo')
  |> :public_key.pem_encode()
```

### Device ID — SHA-256 of Raw Public Key Bytes

The device ID is NOT a UUID. It is the SHA-256 hex fingerprint of the raw public key:

```elixir
[{_, der}] = :public_key.pem_decode(public_key_pem)
raw_pub = :public_key.der_decode(:'SubjectPublicKeyInfo', der)
device_id = :crypto.hash(:sha256, raw_pub) |> Base.hex_encode_to_string()
# 64-char hex string, e.g. "a1b2c3d4...f9e8d7c6"
```

### Signature Payload — Pipe-Delimited String

```elixir
# v3 payload
payload = [
  "v3",
  device_id,
  client_id,       # "openclaw-mq"
  client_mode,     # "node"
  role,            # "node"
  scopes_str,      # "" or "admin,write"
  Integer.to_string(signed_at_ms),
  gateway_token,
  nonce,
  platform,        # "elixir"
  device_family    # "null"
] |> Enum.join("|")

# Sign with Ed25519 → DER → Base64URL
der_sig = :crypto.sign(:ed25519, payload, private_key)
signature = Base.url_encode64(der_sig, padding: false)
```

### Identity File — `~/.openclaw/iamq-device-identity.json`

```json
{
  "version": 1,
  "deviceId": "<sha256-hex-of-raw-public-key>",
  "createdAtMs": 1744089600000,
  "privateKeyPem": "-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----",
  "publicKeyPem": "-----BEGIN PUBLIC KEY-----\n...\n-----END PUBLIC KEY-----"
}
```

### New Module: `OpenclawMq.Gateway.DeviceIdentity`

Create at `openclaw_mq/lib/openclaw_mq/gateway/device_identity.ex`:

- `get_or_create_identity/0` — load from disk or generate new Ed25519 keypair
- `regenerate_identity/0` — force new keypair (invalidates old device on gateway)
- Device ID derived as SHA-256 of raw public key bytes
- Reads identity from `~/.openclaw/iamq-device-identity.json`

### Corrected RpcClient State Machine

States: `:idle → :waiting_challenge → :authenticated → :closing → :done`

1. Connect to gateway WS → server sends `{"type":"event","event":"connect.challenge","payload":{"nonce":"...","ts":...}}`
2. Client responds with `connect.auth` req containing token, nonce, signed payload
3. Server sends `connect.success` → client sends the actual RPC req
4. Receive `res` response → forward to caller → close

### Corrected `connect.req` (v3, recommended)

```json
{
  "type": "req", "id": "<uuid>",
  "method": "connect",
  "params": {
    "minProtocol": 3, "maxProtocol": 3,
    "client": {
      "id": "openclaw-mq", "version": "1.0.0",
      "platform": "elixir", "mode": "node", "deviceFamily": null
    },
    "role": "node", "scopes": [],
    "auth": {"token": "<OPENCLAW_GATEWAY_TOKEN>"},
    "locale": "en-US", "userAgent": "openclaw-mq/1.0.0",
    "device": {
      "id": "<sha256-hex-of-public-key>",
      "publicKey": "<PEM or base64url raw>",
      "signature": "<base64url(Ed25519.sign(payload)))>",
      "signedAt": 1744089600000,
      "nonce": "<nonce from challenge>"
    }
  }
}
```

### Files to Create/Modify

| File | Action |
|------|--------|
| `openclaw_mq/lib/openclaw_mq/gateway/device_identity.ex` | **Create** — Ed25519 key generation, device ID, identity persistence |
| `openclaw_mq/lib/openclaw_mq/gateway/rpc_client.ex` | **Replace** — Full state machine with Ed25519 signing, pipe-delimited payload |
| `openclaw_mq/lib/openclaw_mq/gateway/dispatcher.ex` | **Update** — Init DeviceIdentity; update gateway RPC payload format |
| `openclaw_mq/config/config.exs` | **No change** — Already has `gateway_url`, `gateway_token`, `gateway_rpc_enabled` |

---

*Add new entries above this line.*
