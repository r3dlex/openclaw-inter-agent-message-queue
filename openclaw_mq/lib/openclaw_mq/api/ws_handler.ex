# :nocov: — WebSocket upgrade handler; requires live Cowboy WS connection, not unit-testable
defmodule OpenclawMq.Api.WsHandler do
  @moduledoc """
  WebSocket handler for real-time push to agents.

  Agents connect to ws://localhost:18793/ws and send:
    {"action": "register", "agent_id": "mail_agent"}

  They then receive pushed messages in real-time:
    {"event": "new_message", "message": {...}}
  """
  @behaviour :cowboy_websocket

  require Logger

  @impl true
  def init(req, _state) do
    {:cowboy_websocket, req, %{agent_id: nil}, %{idle_timeout: 300_000}}
  end

  @impl true
  def websocket_init(state) do
    {:ok, state}
  end

  @impl true
  def websocket_handle({:text, raw}, state) do
    case Jason.decode(raw) do
      {:ok, %{"action" => "register", "agent_id" => agent_id}} ->
        # Subscribe this WS connection to the agent's PubSub topic
        Phoenix.PubSub.subscribe(OpenclawMq.PubSub, "agent:#{agent_id}")
        Phoenix.PubSub.subscribe(OpenclawMq.PubSub, "broadcast")
        OpenclawMq.Registry.register(agent_id)

        Logger.info("[WS] Agent #{agent_id} connected via WebSocket")

        reply = Jason.encode!(%{"event" => "registered", "agent_id" => agent_id})
        {:reply, {:text, reply}, %{state | agent_id: agent_id}}

      {:ok, %{"action" => "heartbeat"}} ->
        if state.agent_id do
          OpenclawMq.Registry.heartbeat(state.agent_id)
        end

        reply = Jason.encode!(%{"event" => "heartbeat_ack"})
        {:reply, {:text, reply}, state}

      {:ok, %{"action" => "send"} = payload} ->
        case OpenclawMq.Message.new(payload) do
          {:ok, msg} ->
            :ok = OpenclawMq.Store.put(msg)
            reply = Jason.encode!(%{"event" => "sent", "id" => msg.id})
            {:reply, {:text, reply}, state}

          {:error, reason} ->
            reply = Jason.encode!(%{"event" => "error", "reason" => reason})
            {:reply, {:text, reply}, state}
        end

      {:ok, %{"action" => "ack", "id" => msg_id}} ->
        OpenclawMq.Store.update_status(msg_id, "read")
        {:ok, state}

      {:error, _} ->
        reply = Jason.encode!(%{"event" => "error", "reason" => "invalid JSON"})
        {:reply, {:text, reply}, state}

      _ ->
        reply = Jason.encode!(%{"event" => "error", "reason" => "unknown action"})
        {:reply, {:text, reply}, state}
    end
  end

  @impl true
  def websocket_handle(_frame, state) do
    {:ok, state}
  end

  @impl true
  def websocket_info({:new_message, msg}, state) do
    payload =
      Jason.encode!(%{
        "event" => "new_message",
        "message" => OpenclawMq.Message.to_map(msg)
      })

    {:reply, {:text, payload}, state}
  end

  @impl true
  def websocket_info(_info, state) do
    {:ok, state}
  end

  @impl true
  def terminate(_reason, _req, %{agent_id: agent_id}) when is_binary(agent_id) do
    Logger.info("[WS] Agent #{agent_id} disconnected")
    :ok
  end

  def terminate(_reason, _req, _state), do: :ok
end
