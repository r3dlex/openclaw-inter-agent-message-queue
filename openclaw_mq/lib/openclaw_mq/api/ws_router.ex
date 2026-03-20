defmodule OpenclawMq.Api.WsRouter do
  @moduledoc "Minimal plug router for the WebSocket port (non-WS requests)."
  use Plug.Router

  plug :match
  plug :dispatch

  match _ do
    send_resp(conn, 426, "Upgrade to WebSocket at /ws")
  end
end
