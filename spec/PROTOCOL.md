# Inter-Agent Message Queue Protocol

## Location

All agent inboxes live under `queue/` in this repository.

## Structure

```
queue/
  broadcast/           <- messages for ALL agents
  main/                <- inbox for main
  mq_agent/            <- inbox for mq_agent (this agent)
  mail_agent/          <- inbox for mail_agent
  librarian_agent/     <- inbox for librarian_agent
  journalist_agent/    <- inbox for journalist_agent
  instagram_agent/     <- inbox for instagram_agent
  workday_agent/       <- inbox for workday_agent
  gitrepo_agent/       <- inbox for gitrepo_agent
  sysadmin_agent/      <- inbox for sysadmin_agent
  health_fitness/      <- inbox for health_fitness
  agent_claude/        <- inbox for agent_claude
  archivist_agent/     <- inbox for archivist_agent
```

New agents get a folder created during registration. The Elixir service (via the HTTP API) is the primary messaging channel; the file-based queue is a fallback and archive.

## Message Format

Each message is a single JSON file. Filename format: `{timestamp}-{from_agent}.json`

Example: `2026-03-20T21-30-00Z-mail_agent.json`

```json
{
  "id": "uuid-v4",
  "from": "mail_agent",
  "to": "librarian_agent",
  "priority": "NORMAL",
  "type": "request",
  "subject": "Short summary of the message",
  "body": "Full message content. Can be multi-line.",
  "replyTo": null,
  "createdAt": "2026-03-20T21:30:00Z",
  "expiresAt": null,
  "status": "unread"
}
```

### Field Reference

- `id`: UUID v4. Unique message identifier.
- `from`: Agent ID of the sender.
- `to`: Agent ID of the recipient. Use `"broadcast"` for broadcast messages.
- `priority`: `URGENT`, `HIGH`, `NORMAL`, or `LOW`.
- `type`: `request` (needs action), `response` (reply to a request), `info` (FYI, no action needed), `error` (something went wrong).
- `subject`: One-line summary. Keep it under 80 characters.
- `body`: Full message. Plain text or markdown.
- `replyTo`: The `id` of the message this responds to. Null if not a reply.
- `createdAt`: ISO-8601 timestamp.
- `expiresAt`: ISO-8601 timestamp or null. Messages past expiry can be archived or deleted.
- `status`: `unread`, `read`, `acted`, `archived`.

## Rules

### Sending

1. To send a direct message: write the JSON file to `queue/{recipient_agent_id}/`.
2. To broadcast: write the JSON file to `queue/broadcast/`.
3. Use the filename format `{ISO-timestamp}-{your_agent_id}.json`. Replace colons with dashes in the timestamp.
4. Never modify a message after writing it. To update status, the recipient renames or moves the file.

### Receiving

1. On every session start, check your inbox (`queue/{your_agent_id}/`) and `queue/broadcast/`.
2. Process messages in chronological order (sort by filename).
3. After reading a message, update `status` to `read`.
4. After acting on it, update `status` to `acted`.
5. To reply, create a new message file in the sender's inbox with `replyTo` set to the original `id`.

### Cleanup

1. Messages with `status: "acted"` older than 7 days can be deleted or moved to `queue/{agent}/archive/`.
2. Messages past `expiresAt` can be deleted without processing.
3. Each agent is responsible for cleaning its own inbox.

## Examples

### mail_agent asks librarian_agent to research a topic

File: `queue/librarian_agent/2026-03-20T21-30-00Z-mail_agent.json`

```json
{
  "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "from": "mail_agent",
  "to": "librarian_agent",
  "priority": "HIGH",
  "type": "request",
  "subject": "Research eTendering escalation for 26.2",
  "body": "Received an email from PM about eTendering blockers in 26.2 release. Need a summary of known issues and recent commits. Check GitHub issues tagged 'etendering' in the main repo.",
  "replyTo": null,
  "createdAt": "2026-03-20T21:30:00Z",
  "expiresAt": "2026-03-21T21:30:00Z",
  "status": "unread"
}
```

### librarian_agent replies

File: `queue/mail_agent/2026-03-20T22-15-00Z-librarian_agent.json`

```json
{
  "id": "f9e8d7c6-b5a4-3210-fedc-ba0987654321",
  "from": "librarian_agent",
  "to": "mail_agent",
  "priority": "HIGH",
  "type": "response",
  "subject": "Re: Research eTendering escalation for 26.2",
  "body": "Found 3 open issues tagged etendering for 26.2. Two are blockers (auth timeout, batch import failure). One is enhancement (UI filter). Last commit touching etendering was 2 days ago by user X. Details attached in body.",
  "replyTo": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "createdAt": "2026-03-20T22:15:00Z",
  "expiresAt": null,
  "status": "unread"
}
```

### main broadcasts a system-wide notice

File: `queue/broadcast/2026-03-20T06-00-00Z-main.json`

```json
{
  "id": "11223344-5566-7788-99aa-bbccddeeff00",
  "from": "main",
  "to": "broadcast",
  "priority": "NORMAL",
  "type": "info",
  "subject": "Model switched to MiniMax-M2.5",
  "body": "All agents now run MiniMax-M2.5 as default. M2.7 is not yet available on the oauth endpoint.",
  "replyTo": null,
  "createdAt": "2026-03-20T06:00:00Z",
  "expiresAt": "2026-03-27T06:00:00Z",
  "status": "unread"
}
```
