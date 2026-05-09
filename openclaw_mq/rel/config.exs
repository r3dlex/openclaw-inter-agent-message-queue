import Config

# Runtime configuration for the Elixir release.
# Config.Release reads env vars at application startup (not at build time).
Config.Release(
  :openclaw_mq,
  [],
  gateway_url: System.get_env("OPENCLAW_GATEWAY_URL") || "ws://127.0.0.1:18789",
  gateway_token: System.get_env("OPENCLAW_GATEWAY_TOKEN") || "",
  gateway_rpc_enabled: System.get_env("IAMQ_GATEWAY_RPC_ENABLED") != "false"
)
