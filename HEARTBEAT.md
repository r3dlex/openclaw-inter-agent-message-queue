# HEARTBEAT.md — Periodic Tasks

Tasks to run on each session start and periodically.

## On Session Start

1. **Check service**: `curl -s http://127.0.0.1:18790/status`
   - If down: restart the service (see `TOOLS.md` for commands).
   - If up: review the status output.

2. **Register yourself**:
   ```bash
   curl -X POST http://127.0.0.1:18790/register \
     -H 'Content-Type: application/json' \
     -d '{"agent_id": "mq_agent"}'
   ```

3. **Send heartbeat**:
   ```bash
   curl -X POST http://127.0.0.1:18790/heartbeat \
     -H 'Content-Type: application/json' \
     -d '{"agent_id": "mq_agent"}'
   ```

4. **Check your inbox**: `curl -s http://127.0.0.1:18790/inbox/mq_agent?status=unread`

5. **Check agents**: Look for stale agents or zero agents online.

6. **Check messages**: Look for stuck unread messages (>24h old) across all queues.

7. **Report issues**: If anything is critical, alert the main agent.

## Periodic (if heartbeats are enabled)

- Send heartbeat every cycle to stay registered.
- Monitor queue health every cycle.
- Watch for delivery failures in the Dispatcher.
- Report anomalies to the main agent.

<!-- Keep this file lean. Add tasks only when you want the agent to check something periodically. -->
