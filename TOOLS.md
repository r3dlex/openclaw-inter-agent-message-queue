# TOOLS.md — Environment Notes

Notes specific to this deployment. Update as your environment changes.

## Service Endpoints

- HTTP API: `http://127.0.0.1:18790`
- WebSocket: `ws://127.0.0.1:18791/ws`
- OpenClaw Gateway: `ws://127.0.0.1:18789`

## Key Commands

```bash
# Check service health
curl -s http://127.0.0.1:18790/status | python3 -m json.tool

# List online agents
curl -s http://127.0.0.1:18790/agents | python3 -m json.tool

# Start service (development)
cd openclaw_mq && mix run --no-halt

# Start service (production release)
openclaw_mq/_build/prod/rel/openclaw_mq/bin/openclaw_mq start

# Run monitoring pipeline
python3 -m tools.pipeline_runner.cli monitor

# View logs (if running as LaunchAgent)
tail -f /tmp/openclaw/openclaw-mq.log
```

## Logs

- Service stdout: `/tmp/openclaw/openclaw-mq.log`
- Service stderr: `/tmp/openclaw/openclaw-mq.err.log`

## Notes

- Add environment-specific details here (camera names, SSH hosts, device nicknames, etc.)
- This file is yours — update it as you learn about the environment.
