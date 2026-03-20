# HEARTBEAT.md — Periodic Tasks

Tasks to run on each session start and periodically.

## On Session Start

1. **Check service**: `curl -s http://127.0.0.1:18790/status`
   - If down: restart the service (see `TOOLS.md` for commands).
   - If up: review the status output.

2. **Check agents**: Look for stale agents or zero agents online.

3. **Check messages**: Look for stuck unread messages (>24h old).

4. **Report issues**: If anything is critical, alert the main agent.

## Periodic (if heartbeats are enabled)

- Monitor queue health every cycle.
- Watch for delivery failures in the Dispatcher.
- Report anomalies to the main agent.

<!-- Keep this file lean. Add tasks only when you want the agent to check something periodically. -->
