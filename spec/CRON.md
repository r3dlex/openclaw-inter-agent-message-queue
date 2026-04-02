# Cron Subsystem

The IAMQ cron subsystem lets agents schedule recurring tasks without managing their own timers. At each matching UTC wall-clock minute IAMQ delivers a `cron::<name>` message directly to the agent's inbox.

## Design

- **`Cron.Entry`** — struct representing a registered schedule (id, agent_id, name, expression, enabled, timestamps).
- **`Cron.Store`** — ETS-backed store with optional DETS persistence across restarts. Table name: `:cron_entries`.
- **`Cron.Scheduler`** — GenServer that loads enabled entries on start, schedules each one with `Process.send_after/3`, and re-schedules after each fire.

### Cron message format

When a cron fires, the scheduler calls `OpenclawMq.Store.put/1` with:

```json
{
  "from": "iamq",
  "to": "<agent_id>",
  "type": "info",
  "subject": "cron::<name>",
  "priority": "normal",
  "body": {
    "cron_id": "<uuid>",
    "expression": "30 6 * * *",
    "fired_at": "2026-04-02T06:30:00Z"
  }
}
```

## Expression format

Standard 5-field cron, UTC:

```
min hour dom month dow
 *    *    *    *    *
```

| Field  | Range | Notes          |
|--------|-------|----------------|
| min    | 0–59  | `*/n` and `a-b` supported |
| hour   | 0–23  |                |
| dom    | 1–31  |                |
| month  | 1–12  |                |
| dow    | 0–7   | 0 and 7 = Sunday |

Examples:

| Expression    | Meaning                         |
|---------------|---------------------------------|
| `0 8 * * *`   | Every day at 08:00 UTC          |
| `30 6 * * 1`  | Every Monday at 06:30 UTC       |
| `*/5 * * * *` | Every 5 minutes                 |
| `0 0 1 * *`   | First day of each month at midnight |

## API

See [API.md](API.md) for the full HTTP reference (`POST /crons`, `GET /crons`, `PATCH /crons/:id`, `DELETE /crons/:id`).

## Dependency injection (testing)

The scheduler resolves its store and dispatcher at runtime via application env so tests can substitute doubles:

```elixir
Application.put_env(:openclaw_mq, :store_mod, MyFakeStore)
Application.put_env(:openclaw_mq, :dispatcher_mod, MyFakeDispatcher)
```

## Persistence

Cron entries survive restarts because `Cron.Store` syncs to DETS on every write. The DETS file path defaults to `priv/crons.dets` and is configurable via:

```elixir
config :openclaw_mq, cron_dets_path: "priv/crons.dets"
config :openclaw_mq, cron_dets_enabled: true
```

Set `cron_dets_enabled: false` in test config to keep tests isolated.

---
*Owner: mq_agent*
