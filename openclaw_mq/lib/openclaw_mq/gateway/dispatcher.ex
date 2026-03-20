defmodule OpenclawMq.Gateway.Dispatcher do
  @moduledoc """
  Triggers an OpenClaw agent when a message arrives.
  Tries gateway WebSocket RPC first, falls back to CLI.
  """
  use GenServer

  require Logger

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc "Deliver a message to an agent by triggering it."
  def deliver(agent_id, %OpenclawMq.Message{} = msg) do
    GenServer.cast(__MODULE__, {:deliver, agent_id, msg})
  end

  # Server

  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_cast({:deliver, agent_id, msg}, state) do
    case try_gateway_rpc(agent_id, msg) do
      :ok ->
        Logger.info("[Dispatcher] Delivered to #{agent_id} via gateway RPC")

      {:error, reason} ->
        Logger.warn("[Dispatcher] Gateway RPC failed for #{agent_id}: #{reason}. Falling back to CLI.")
        try_cli(agent_id, msg)
    end

    {:noreply, state}
  end

  defp try_gateway_rpc(agent_id, msg) do
    gateway_url = Application.get_env(:openclaw_mq, :gateway_url)
    gateway_token = Application.get_env(:openclaw_mq, :gateway_token)

    # Build the RPC payload
    payload =
      Jason.encode!(%{
        "type" => "agent.message",
        "agentId" => agent_id,
        "message" => %{
          "text" =>
            "[MQ] New message from #{msg.from}: #{msg.subject}\n\n" <>
              "Check your inbox at http://127.0.0.1:18790/inbox/#{agent_id}?status=unread"
        },
        "auth" => %{"token" => gateway_token}
      })

    # Attempt a quick WS connection, send, close
    case WebSockex.start("#{gateway_url}", OpenclawMq.Gateway.RpcClient, %{
           payload: payload,
           caller: self()
         }) do
      {:ok, pid} ->
        receive do
          {:rpc_result, :ok} -> :ok
          {:rpc_result, {:error, reason}} -> {:error, reason}
        after
          5_000 ->
            Process.exit(pid, :kill)
            {:error, "gateway RPC timeout"}
        end

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  defp try_cli(agent_id, msg) do
    openclaw_bin = Application.get_env(:openclaw_mq, :openclaw_bin)

    prompt =
      "[MQ] New message from #{msg.from} (#{msg.priority}): #{msg.subject}. " <>
        "Read it at http://127.0.0.1:18790/inbox/#{agent_id}?status=unread"

    case System.cmd(openclaw_bin, ["run", agent_id, "--message", prompt], stderr_to_stdout: true) do
      {output, 0} ->
        Logger.info("[Dispatcher] CLI delivery to #{agent_id} succeeded")
        :ok

      {output, code} ->
        Logger.error("[Dispatcher] CLI delivery to #{agent_id} failed (exit #{code}): #{output}")
        {:error, "CLI exit #{code}"}
    end
  end
end
