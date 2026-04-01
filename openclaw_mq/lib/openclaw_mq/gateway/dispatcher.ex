defmodule OpenclawMq.Gateway.Dispatcher do
  @moduledoc """
  Delivers messages to agents using a tiered strategy:

  1. **WebSocket push** — If the agent has an active WS connection to :18793/ws,
     `Store.put/1` already broadcasts via PubSub. No dispatcher action needed.
  2. **HTTP callback** — If the agent registered a callback URL via `POST /callback`,
     the dispatcher POSTs the full message JSON to that URL.
  3. **Passive inbox** — The message sits in the ETS store. The agent picks it up
     on its next heartbeat poll of `GET /inbox/:agent_id?status=unread`.

  Gateway WS RPC (port 18789) is available but disabled by default due to
  protocol mismatch (challenge-response handshake not yet implemented).
  Enable with `IAMQ_GATEWAY_RPC_ENABLED=true`.
  """
  use GenServer

  require Logger

  # Callback registry ETS table
  @callback_table :openclaw_mq_callbacks

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc "Register a callback URL for an agent."
  def register_callback(agent_id, url) do
    GenServer.call(__MODULE__, {:register_callback, agent_id, url})
  end

  @doc "Remove a callback URL for an agent."
  def unregister_callback(agent_id) do
    GenServer.call(__MODULE__, {:unregister_callback, agent_id})
  end

  @doc "Get the callback URL for an agent, if any."
  def get_callback(agent_id) do
    GenServer.call(__MODULE__, {:get_callback, agent_id})
  end

  @doc "Deliver a message to an agent. Tries HTTP callback, then gateway RPC if enabled."
  def deliver(agent_id, %OpenclawMq.Message{} = msg) do
    GenServer.cast(__MODULE__, {:deliver, agent_id, msg})
  end

  # Server

  @impl true
  def init(_state) do
    :ets.new(@callback_table, [:named_table, :set, :public, read_concurrency: true])
    {:ok, %{}}
  end

  @impl true
  def handle_call({:register_callback, agent_id, url}, _from, state) do
    :ets.insert(@callback_table, {agent_id, url})
    Logger.info("[Dispatcher] Callback registered for #{agent_id}: #{url}")
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:unregister_callback, agent_id}, _from, state) do
    :ets.delete(@callback_table, agent_id)
    Logger.info("[Dispatcher] Callback removed for #{agent_id}")
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:get_callback, agent_id}, _from, state) do
    result =
      case :ets.lookup(@callback_table, agent_id) do
        [{^agent_id, url}] -> {:ok, url}
        [] -> :none
      end

    {:reply, result, state}
  end

  @impl true
  def handle_cast({:deliver, agent_id, msg}, state) do
    # Tier 1: WebSocket push is handled by PubSub in Store.put/1 — nothing to do here.

    # Tier 2: HTTP callback
    case :ets.lookup(@callback_table, agent_id) do
      [{^agent_id, url}] ->
        case try_http_callback(url, msg) do
          :ok ->
            Logger.info("[Dispatcher] Delivered to #{agent_id} via HTTP callback")

          {:error, reason} ->
            Logger.warning(
              "[Dispatcher] HTTP callback failed for #{agent_id}: #{inspect(reason)}. " <>
                "Message remains in inbox for passive pickup."
            )

            maybe_try_gateway_rpc(agent_id, msg)
        end

      [] ->
        maybe_try_gateway_rpc(agent_id, msg)
    end

    {:noreply, state}
  end

  # --- Tier 2: HTTP callback ---

  defp try_http_callback(url, msg) do
    body = Jason.encode!(OpenclawMq.Message.to_map(msg))

    :inets.start()
    :ssl.start()

    url_charlist = String.to_charlist(url)

    case :httpc.request(
           :post,
           {url_charlist, [{~c"content-type", ~c"application/json"}], ~c"application/json",
            String.to_charlist(body)},
           [{:timeout, 5_000}, {:connect_timeout, 3_000}],
           []
         ) do
      {:ok, {{_, status, _}, _headers, _body}} when status in 200..299 ->
        :ok

      {:ok, {{_, status, _}, _headers, resp_body}} ->
        {:error, "HTTP #{status}: #{List.to_string(resp_body) |> String.slice(0, 200)}"}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  # --- Tier 3: Gateway WS RPC (optional, disabled by default) ---

  defp maybe_try_gateway_rpc(agent_id, msg) do
    if Application.get_env(:openclaw_mq, :gateway_rpc_enabled, false) do
      case try_gateway_rpc(agent_id, msg) do
        :ok ->
          Logger.info("[Dispatcher] Delivered to #{agent_id} via gateway RPC")

        {:error, reason} ->
          Logger.warning(
            "[Dispatcher] Gateway RPC failed for #{agent_id}: #{inspect(reason)}. " <>
              "Falling back to CLI."
          )

          try_cli_fallback(agent_id, msg)
      end
    else
      Logger.debug("[Dispatcher] No callback for #{agent_id}; trying CLI fallback.")
      try_cli_fallback(agent_id, msg)
    end
  end

  defp try_cli_fallback(agent_id, msg) do
    case try_cli(agent_id, msg) do
      :ok ->
        Logger.info("[Dispatcher] Delivered to #{agent_id} via CLI")

      {:error, reason} ->
        Logger.warning(
          "[Dispatcher] CLI fallback failed for #{agent_id}: #{inspect(reason)}. " <>
            "Message remains in inbox for passive pickup."
        )
    end
  end

  defp try_gateway_rpc(agent_id, msg) do
    gateway_url = Application.get_env(:openclaw_mq, :gateway_url)
    gateway_token = Application.get_env(:openclaw_mq, :gateway_token)

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

    case WebSockex.start("#{gateway_url}/ws", OpenclawMq.Gateway.RpcClient, %{
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

  # --- CLI fallback ---

  defp try_cli(agent_id, msg) do
    openclaw_bin = Application.get_env(:openclaw_mq, :openclaw_bin, "openclaw")

    notification =
      "[MQ] New message from #{msg.from} (#{msg.priority}): #{msg.subject}. " <>
        "Check your inbox: curl http://127.0.0.1:18790/inbox/#{agent_id}?status=unread"

    # Use `openclaw agent --agent <id> --message <text>` to wake the agent
    case System.cmd(openclaw_bin, ["agent", "--agent", agent_id, "--message", notification],
           stderr_to_stdout: true
         ) do
      {_output, 0} ->
        :ok

      {output, code} ->
        Logger.warning(
          "[Dispatcher] CLI `openclaw agent` failed for #{agent_id} (exit #{code}): " <>
            String.slice(output, 0, 300)
        )
    end
  end
end
