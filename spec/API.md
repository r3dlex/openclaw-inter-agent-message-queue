# API Reference

The Elixir service exposes two interfaces:

- **HTTP API**: `http://127.0.0.1:18790` (configurable via `IAMQ_HTTP_PORT`)
- **WebSocket**: `ws://127.0.0.1:18791/ws` (configurable via `IAMQ_WS_PORT`)

---

## HTTP Endpoints

### `POST /register`

Register an agent as online.

**Body**:
```json
{ "agent_id": "mail_agent" }
```

**Response** `200`:
```json
{ "status": "registered", "agent_id": "mail_agent" }
```

### `POST /heartbeat`

Send a heartbeat (auto-registers if unknown).

**Body**:
```json
{ "agent_id": "mail_agent" }
```

### `POST /send`

Send a message to an agent or broadcast.

**Body**:
```json
{
  "from": "mail_agent",
  "to": "librarian_agent",
  "type": "request",
  "priority": "HIGH",
  "subject": "Research eTendering",
  "body": "Need a summary of known issues for 26.2",
  "replyTo": null,
  "expiresAt": null
}
```

Use `"to": "broadcast"` to send to all agents.

**Response** `201`: The created message object.

### `GET /inbox/:agent_id`

Get messages for an agent (direct + broadcast).

Optional query: `?status=unread`

**Response** `200`:
```json
{
  "messages": [
    {
      "id": "uuid",
      "from": "mail_agent",
      "to": "librarian_agent",
      "priority": "HIGH",
      "type": "request",
      "subject": "Research eTendering",
      "body": "...",
      "replyTo": null,
      "createdAt": "2026-03-20T21:30:00Z",
      "expiresAt": null,
      "status": "unread"
    }
  ]
}
```

### `PATCH /messages/:id`

Update message status.

**Body**:
```json
{ "status": "read" }
```

Valid statuses: `unread`, `read`, `acted`, `archived`.

### `GET /status`

Queue health summary.

**Response** `200`:
```json
{
  "checkedAt": "2026-03-21T12:00:00Z",
  "queues": {
    "mail_agent": { "unread": 2, "read": 5, "acted": 10, "oldest_unread": "2026-03-21T08:00:00Z" },
    "broadcast": { "unread": 0, "read": 1, "acted": 3, "oldest_unread": null }
  },
  "agents_online": [
    { "id": "mail_agent", "registered_at": 123456, "last_heartbeat": 123789 }
  ]
}
```

### `GET /agents`

List registered agents.

**Response** `200`:
```json
{
  "agents": [
    { "id": "mail_agent", "registered_at": 123456, "last_heartbeat": 123789 }
  ]
}
```

---

## WebSocket Protocol

Connect to `ws://127.0.0.1:18791/ws`.

### Client → Server

| Action      | Payload | Effect |
|-------------|---------|--------|
| `register`  | `{"action": "register", "agent_id": "mail_agent"}` | Subscribe to PubSub topics |
| `heartbeat` | `{"action": "heartbeat"}` | Update heartbeat timestamp |
| `send`      | `{"action": "send", "from": "...", "to": "...", "type": "...", "subject": "...", "body": "..."}` | Store and broadcast message |
| `ack`       | `{"action": "ack", "id": "msg-uuid"}` | Mark message as `read` |

### Server → Client

| Event           | When |
|-----------------|------|
| `registered`    | After successful register |
| `heartbeat_ack` | After heartbeat |
| `sent`          | After send (includes message `id`) |
| `error`         | On invalid JSON or unknown action |
| `new_message`   | Real-time push when a message arrives for this agent |

### Example

```javascript
const ws = new WebSocket("ws://127.0.0.1:18791/ws");
ws.onopen = () => ws.send(JSON.stringify({action: "register", agent_id: "mail_agent"}));
ws.onmessage = (e) => console.log(JSON.parse(e.data));
```
