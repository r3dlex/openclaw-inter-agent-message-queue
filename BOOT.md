# BOOT.md — Startup Instructions

On startup (when `hooks.internal.enabled` is set):

1. Check if the Elixir MQ service is running: `curl -s http://127.0.0.1:18790/status`
2. If not running, start it (see `TOOLS.md` for commands).
3. **Register yourself** with the service:
   ```bash
   curl -X POST http://127.0.0.1:18790/register \
     -H 'Content-Type: application/json' \
     -d '{"agent_id": "mq_agent"}'
   ```
4. Check your inbox: `curl -s http://127.0.0.1:18790/inbox/mq_agent?status=unread`
5. Send a status summary to the main agent if there are issues.
6. Reply with NO_REPLY after any message-sending actions.
