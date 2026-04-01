# :nocov: — Ephemeral WebSockex client; requires live gateway WS connection, not unit-testable
defmodule OpenclawMq.Gateway.RpcClient do
  @moduledoc """
  Ephemeral WebSocket client for sending a single RPC message
  to the OpenClaw gateway, then disconnecting.
  """
  use WebSockex

  require Logger

  @impl true
  def handle_connect(_conn, %{payload: payload, caller: _caller} = state) do
    # Send the payload immediately upon connection
    {:reply, {:text, payload}, state}
  end

  @impl true
  def handle_frame({:text, response}, %{caller: caller} = state) do
    case Jason.decode(response) do
      {:ok, %{"error" => err}} ->
        send(caller, {:rpc_result, {:error, err}})

      {:ok, _} ->
        send(caller, {:rpc_result, :ok})

      {:error, _} ->
        send(caller, {:rpc_result, {:error, "invalid JSON from gateway"}})
    end

    {:close, state}
  end

  @impl true
  def handle_frame(_frame, state) do
    {:ok, state}
  end

  @impl true
  def handle_disconnect(_reason, state) do
    {:ok, state}
  end
end
