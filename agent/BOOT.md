# BOOT.md — Startup Instructions

On startup (when `hooks.internal.enabled` is set):

1. Check if the Elixir MQ service is running.
2. If not running, start it.
3. Send a status summary to the main agent if there are issues.
4. Reply with NO_REPLY after any message-sending actions.
