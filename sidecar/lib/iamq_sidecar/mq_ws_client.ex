defmodule IamqSidecar.MqWsClient do
  @moduledoc """
  WebSocket client for real-time IAMQ message push.

  Connects to the IAMQ WebSocket endpoint, registers, sends periodic
  heartbeats, and receives messages instantly without polling delay.
  Auto-reconnects on disconnect.

  Env vars:
    IAMQ_WS_URL   (default ws://127.0.0.1:18793/ws)
    IAMQ_AGENT_ID  (required)
  """
  use WebSockex
  require Logger

  @default_ws_url "ws://127.0.0.1:18793/ws"
  @heartbeat_interval 30_000
  @reconnect_interval 15_000

  def start_link(_opts) do
    ws_url = System.get_env("IAMQ_WS_URL", @default_ws_url)
    agent_id = System.fetch_env!("IAMQ_AGENT_ID")

    state = %{agent_id: agent_id, ws_url: ws_url}

    WebSockex.start_link(ws_url, __MODULE__, state,
      name: __MODULE__,
      handle_initial_conn_failure: true
    )
  end

  # --- callbacks ---

  @impl true
  def handle_connect(_conn, state) do
    Logger.info("[MQ-WS] Connected to #{state.ws_url}")
    send(self(), :do_register)
    {:ok, state}
  end

  @impl true
  def handle_frame({:text, raw}, state) do
    case Jason.decode(raw) do
      {:ok, %{"event" => "registered", "agent_id" => id}} ->
        Logger.info("[MQ-WS] Registered as #{id}")
        {:ok, state}

      {:ok, %{"event" => "heartbeat_ack"}} ->
        {:ok, state}

      {:ok, %{"event" => "sent", "id" => id}} ->
        Logger.debug("[MQ-WS] Sent confirmed: #{id}")
        {:ok, state}

      {:ok, %{"event" => "new_message", "message" => msg}} ->
        handle_push(msg)
        {:ok, state}

      {:ok, %{"event" => "error", "reason" => reason}} ->
        Logger.warning("[MQ-WS] Server error: #{reason}")
        {:ok, state}

      _ ->
        {:ok, state}
    end
  end

  def handle_frame(_other, state), do: {:ok, state}

  @impl true
  def handle_info(:do_register, state) do
    frame = Jason.encode!(%{action: "register", agent_id: state.agent_id})
    Process.send_after(self(), :send_heartbeat, @heartbeat_interval)
    {:reply, {:text, frame}, state}
  end

  def handle_info(:send_heartbeat, state) do
    Process.send_after(self(), :send_heartbeat, @heartbeat_interval)
    {:reply, {:text, Jason.encode!(%{action: "heartbeat"})}, state}
  end

  def handle_info(_msg, state), do: {:ok, state}

  @impl true
  def handle_disconnect(%{reason: reason}, state) do
    Logger.warning(
      "[MQ-WS] Disconnected: #{inspect(reason)}. Reconnecting in #{div(@reconnect_interval, 1000)} s\u2026"
    )

    Process.sleep(@reconnect_interval)
    {:reconnect, state}
  end

  # --- internal ---

  defp handle_push(msg) do
    from = msg["from"] || "unknown"
    subject = msg["subject"] || "(no subject)"
    msg_type = msg["type"] || "info"
    msg_id = msg["id"]

    Logger.info("[MQ-WS] #{msg_type} from #{from}: #{subject}")

    if msg_id do
      try do
        WebSockex.send_frame(__MODULE__, {:text, Jason.encode!(%{action: "ack", id: msg_id})})
      rescue
        _ -> :ok
      end
    end
  end
end
