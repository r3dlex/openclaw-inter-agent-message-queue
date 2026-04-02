import Config

config :openclaw_mq,
  http_port: 18791,
  ws_port: 18794,
  queue_dir: System.tmp_dir!() |> Path.join("openclaw_mq_test"),
  agent_ttl_ms: 300_000,
  reap_interval_ms: 3_600_000,
  gateway_rpc_enabled: false,
  # Disable DETS persistence in tests to keep them fast and side-effect-free
  cron_dets_enabled: false

config :logger, level: :warning
