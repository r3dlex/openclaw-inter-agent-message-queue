defmodule OpenclawMq.Application do
  use Application

  @impl true
  def start(_type, _args) do
    http_port = Application.get_env(:openclaw_mq, :http_port, 18790)
    ws_port = Application.get_env(:openclaw_mq, :ws_port, 18793)

    children = [
      # PubSub backbone
      {Phoenix.PubSub, name: OpenclawMq.PubSub},

      # Agent registry (tracks who is online)
      OpenclawMq.Registry,

      # Message store (in-memory ETS with optional disk persistence)
      OpenclawMq.Store,

      # HTTP API for agents to send/receive/register
      {Plug.Cowboy, scheme: :http, plug: OpenclawMq.Api.Router, port: http_port},

      # WebSocket server for real-time push to agents
      {Plug.Cowboy,
       scheme: :http, plug: OpenclawMq.Api.WsRouter, port: ws_port, dispatch: ws_dispatch()},

      # OpenClaw gateway RPC client (with CLI fallback)
      OpenclawMq.Gateway.Dispatcher,

      # Reaper: cleans up stale agents and expired messages
      OpenclawMq.Reaper
    ]

    opts = [strategy: :one_for_one, name: OpenclawMq.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp ws_dispatch do
    [
      {:_,
       [
         {"/ws", OpenclawMq.Api.WsHandler, []},
         {:_, Plug.Cowboy.Handler, {OpenclawMq.Api.WsRouter, []}}
       ]}
    ]
  end
end
