import Config

config :openclaw_mq,
  http_port: String.to_integer(System.get_env("IAMQ_HTTP_PORT") || "18790"),
  ws_port: String.to_integer(System.get_env("IAMQ_WS_PORT") || "18791"),
  gateway_url: System.get_env("OPENCLAW_GATEWAY_URL") || "ws://127.0.0.1:18789",
  gateway_token: System.get_env("OPENCLAW_GATEWAY_TOKEN") || "",
  gateway_rpc_enabled: System.get_env("IAMQ_GATEWAY_RPC_ENABLED") == "true",
  # How long before an unregistered agent is considered dead
  agent_ttl_ms: String.to_integer(System.get_env("IAMQ_AGENT_TTL_MS") || "300000"),
  # How often to check for stale agents
  reap_interval_ms: String.to_integer(System.get_env("IAMQ_REAP_INTERVAL_MS") || "60000")
