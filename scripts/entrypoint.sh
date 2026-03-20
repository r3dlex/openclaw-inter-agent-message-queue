#!/bin/sh
set -e

case "${1:-serve}" in
  serve)
    echo "Starting OpenClaw MQ (Elixir)..."
    exec /app/release/bin/openclaw_mq start
    ;;
  pipeline)
    shift
    exec python3 -m tools.pipeline_runner.cli "$@"
    ;;
  test)
    cd /app/openclaw_mq
    exec mix test "$@"
    ;;
  shell)
    exec /bin/sh
    ;;
  *)
    exec "$@"
    ;;
esac
