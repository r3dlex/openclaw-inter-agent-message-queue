# API Reference

The Elixir service exposes two interfaces:

- **HTTP API**: `http://127.0.0.1:18790` (configurable via `IAMQ_HTTP_PORT`)
- **WebSocket**: `ws://127.0.0.1:18793/ws` (configurable via `IAMQ_WS_PORT`)

---

## HTTP Endpoints

### `POST /register`

Register an agent as online with optional discovery metadata.

**Body** (minimal):
```json
{ "agent_id": "mail_agent" }
```

**Body** (with metadata):
```json
{
  "agent_id": "mail_agent",
  "name": "Openclaw 🦀",
  "emoji": "🦀",
  "description": "Multi-account email management",
  "capabilities": ["email_send", "email_read", "email_search"]
}
```

Optional metadata fields: `name`, `emoji`, `description`, `capabilities` (array of strings), `workspace`.

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

### `POST /callback`

Register a callback URL for push delivery. When a message arrives for this agent, the dispatcher POSTs the full message JSON to the URL.

**Body**:
```json
{ "agent_id": "mail_agent", "url": "http://localhost:9000/webhook" }
```

**Response** `200`:
```json
{ "status": "callback_registered", "agent_id": "mail_agent", "url": "http://localhost:9000/webhook" }
```

### `DELETE /callback`

Remove a callback URL.

**Body**:
```json
{ "agent_id": "mail_agent" }
```

**Response** `200`:
```json
{ "status": "callback_removed", "agent_id": "mail_agent" }
```

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
    { "id": "mail_agent", "registered_at": "2026-03-21T08:00:00Z", "last_heartbeat": "2026-03-21T12:00:00Z" }
  ]
}
```

### `GET /agents`

List all registered agents with their metadata. This is the primary **agent discovery** endpoint — agents use it to find peers, understand their capabilities, and decide who to message.

**Response** `200`:
```json
{
  "agents": [
    {
      "id": "mail_agent",
      "name": "Openclaw 🦀",
      "emoji": "🦀",
      "description": "Multi-account email management",
      "capabilities": ["email_send", "email_read", "email_search"],
      "registered_at": "2026-03-21T08:00:00Z",
      "last_heartbeat": "2026-03-21T12:00:00Z"
    },
    {
      "id": "librarian_agent",
      "name": "Librarian 📚",
      "emoji": "📚",
      "description": "Document archivist and knowledge organizer",
      "capabilities": ["search", "summarize", "archive"],
      "registered_at": "2026-03-21T08:05:00Z",
      "last_heartbeat": "2026-03-21T11:55:00Z"
    }
  ]
}
```

Metadata fields (`name`, `emoji`, `description`, `capabilities`, `workspace`) are only present if the agent registered them.

### `GET /agents/:agent_id`

Get a single agent's full profile.

**Response** `200`:
```json
{
  "id": "mail_agent",
  "name": "Openclaw 🦀",
  "emoji": "🦀",
  "description": "Multi-account email management",
  "capabilities": ["email_send", "email_read", "email_search"],
  "registered_at": "2026-03-21T08:00:00Z",
  "last_heartbeat": "2026-03-21T12:00:00Z"
}
```

**Response** `404`:
```json
{ "error": "agent not found" }
```

### `PUT /agents/:agent_id`

Update an agent's metadata without re-registering. Merges with existing metadata.

**Body**:
```json
{
  "description": "Updated description",
  "capabilities": ["email_send", "email_read", "email_search", "contact_lookup"]
}
```

**Response** `200`: The updated agent profile (same format as `GET /agents/:agent_id`).

**Response** `404`:
```json
{ "error": "agent not registered" }
```

---

## WebSocket Protocol

Connect to `ws://127.0.0.1:18793/ws`.

### Client → Server

| Action      | Payload | Effect |
|-------------|---------|--------|
| `register`  | `{"action": "register", "agent_id": "mail_agent"}` | Subscribe to PubSub topics |
| `heartbeat` | `{"action": "heartbeat"}` | Update heartbeat timestamp |
| `send`      | `{"action": "send", "from": "...", "to": "...", "type": "...", "subject": "...", "body": "..."}` | Store and broadcast message |
| `ack`       | `{"action": "ack", "id": "msg-uuid"}` | Mark message as `read` (no reply sent) |

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
const ws = new WebSocket("ws://127.0.0.1:18793/ws");
ws.onopen = () => ws.send(JSON.stringify({action: "register", agent_id: "mail_agent"}));
ws.onmessage = (e) => console.log(JSON.parse(e.data));
```
