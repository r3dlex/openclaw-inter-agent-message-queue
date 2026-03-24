defmodule IamqSidecar.MqClient do
  @moduledoc """
  HTTP client GenServer for the OpenClaw Inter-Agent Message Queue.

  All identity is driven by environment variables — the same code runs
  for every agent. See README or docker-compose.yml for the full list.

  Env vars:
    IAMQ_HTTP_URL          (default http://127.0.0.1:18790)
    IAMQ_AGENT_ID          (required)
    IAMQ_AGENT_NAME        (required)
    IAMQ_AGENT_EMOJI       (required)
    IAMQ_AGENT_DESC        (optional)
    IAMQ_AGENT_CAPABILITIES (comma-separated, optional)
    IAMQ_HEARTBEAT_MS      (default 300 000 — 5 min)
    IAMQ_POLL_MS           (default 60 000 — 1 min)
  """
  use GenServer
  require Logger

  @default_url "http://127.0.0.1:18790"
  @default_heartbeat_ms 300_000
  @default_poll_ms 60_000
  @http_timeout 5_000

  # --- public API ---

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def send_message(to, subject, body, opts \\ []),
    do: GenServer.call(__MODULE__, {:send, to, subject, body, opts})

  def broadcast(subject, body, opts \\ []),
    do: send_message("broadcast", subject, body, opts)

  def inbox(status \\ "unread"), do: GenServer.call(__MODULE__, {:inbox, status})
  def ack(message_id, status \\ "read"), do: GenServer.call(__MODULE__, {:ack, message_id, status})
  def agents, do: GenServer.call(__MODULE__, :agents)
  def status, do: GenServer.call(__MODULE__, :status)

  # --- init ---

  @impl true
  def init(state) do
    config = %{
      url: System.get_env("IAMQ_HTTP_URL", @default_url),
      agent_id: System.fetch_env!("IAMQ_AGENT_ID"),
      agent_name: System.fetch_env!("IAMQ_AGENT_NAME"),
      agent_emoji: System.fetch_env!("IAMQ_AGENT_EMOJI"),
      agent_desc: System.get_env("IAMQ_AGENT_DESC", ""),
      agent_caps: parse_caps(System.get_env("IAMQ_AGENT_CAPABILITIES", "")),
      heartbeat_ms: parse_int(System.get_env("IAMQ_HEARTBEAT_MS"), @default_heartbeat_ms),
      poll_ms: parse_int(System.get_env("IAMQ_POLL_MS"), @default_poll_ms)
    }

    state = Map.merge(state, %{config: config, registered: false, consecutive_failures: 0})
    Process.send_after(self(), :register, 2_000)
    {:ok, state}
  end

  # --- handle_info ---

  @impl true
  def handle_info(:register, state) do
    case do_register(state.config) do
      :ok ->
        Logger.info("[MQ] Registered as #{state.config.agent_id}")
        schedule(:heartbeat, state.config.heartbeat_ms)
        schedule(:poll_inbox, state.config.poll_ms)
        {:noreply, %{state | registered: true, consecutive_failures: 0}}

      {:error, reason} ->
        Logger.warning("[MQ] Registration failed: #{inspect(reason)}. Retrying in 30 s…")
        Process.send_after(self(), :register, 30_000)
        {:noreply, %{state | consecutive_failures: state.consecutive_failures + 1}}
    end
  end

  def handle_info(:heartbeat, state) do
    case do_heartbeat(state.config) do
      :ok ->
        schedule(:heartbeat, state.config.heartbeat_ms)
        {:noreply, %{state | consecutive_failures: 0}}

      {:error, _} ->
        failures = state.consecutive_failures + 1

        if failures >= 5 do
          Logger.error("[MQ] 5 consecutive failures — re-registering")
          Process.send_after(self(), :register, 5_000)
          {:noreply, %{state | registered: false, consecutive_failures: failures}}
        else
          schedule(:heartbeat, state.config.heartbeat_ms)
          {:noreply, %{state | consecutive_failures: failures}}
        end
    end
  end

  def handle_info(:poll_inbox, state) do
    case do_poll_inbox(state.config) do
      {:ok, msgs} when msgs != [] -> Enum.each(msgs, &handle_msg(&1, state.config))
      _ -> :ok
    end

    schedule(:poll_inbox, state.config.poll_ms)
    {:noreply, state}
  end

  # --- handle_call ---

  @impl true
  def handle_call({:send, to, subject, body, opts}, _from, state),
    do: {:reply, do_send(state.config, to, subject, body, opts), state}

  def handle_call({:inbox, st}, _from, state), do: {:reply, do_poll_inbox(state.config, st), state}
  def handle_call({:ack, id, st}, _from, state), do: {:reply, do_ack(state.config, id, st), state}
  def handle_call(:agents, _from, state), do: {:reply, do_get(state.config, "/agents"), state}
  def handle_call(:status, _from, state), do: {:reply, do_get(state.config, "/status"), state}

  # --- HTTP helpers ---

  defp do_register(c) do
    payload = %{
      agent_id: c.agent_id,
      name: c.agent_name,
      emoji: c.agent_emoji,
      description: c.agent_desc,
      capabilities: c.agent_caps,
      workspace: File.cwd!()
    }

    case Req.post("#{c.url}/register", json: payload, receive_timeout: @http_timeout) do
      {:ok, %{status: s}} when s in [200, 201] -> :ok
      {:ok, %{status: s, body: b}} -> {:error, "HTTP #{s}: #{inspect(b)}"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_heartbeat(c) do
    case Req.post("#{c.url}/heartbeat", json: %{agent_id: c.agent_id}, receive_timeout: @http_timeout) do
      {:ok, %{status: s}} when s in [200, 201] -> :ok
      {:ok, %{status: s, body: b}} -> {:error, "HTTP #{s}: #{inspect(b)}"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_poll_inbox(c, status \\ "unread") do
    case Req.get("#{c.url}/inbox/#{c.agent_id}", params: [status: status], receive_timeout: @http_timeout) do
      {:ok, %{status: 200, body: %{"messages" => msgs}}} -> {:ok, msgs}
      {:ok, %{status: 200, body: b}} when is_list(b) -> {:ok, b}
      {:ok, %{status: s, body: b}} -> {:error, "HTTP #{s}: #{inspect(b)}"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_send(c, to, subject, body, opts) do
    payload = %{
      from: c.agent_id, to: to,
      type: Keyword.get(opts, :type, "info"),
      priority: Keyword.get(opts, :priority, "NORMAL"),
      subject: subject, body: body,
      replyTo: Keyword.get(opts, :reply_to),
      expiresAt: Keyword.get(opts, :expires_at)
    }

    case Req.post("#{c.url}/send", json: payload, receive_timeout: @http_timeout) do
      {:ok, %{status: s, body: resp}} when s in [200, 201] -> {:ok, resp}
      {:ok, %{status: s, body: b}} -> {:error, "HTTP #{s}: #{inspect(b)}"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_ack(c, message_id, new_status) do
    case Req.patch("#{c.url}/messages/#{message_id}", json: %{status: new_status}, receive_timeout: @http_timeout) do
      {:ok, %{status: s}} when s in [200, 204] -> :ok
      {:ok, %{status: s, body: b}} -> {:error, "HTTP #{s}: #{inspect(b)}"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_get(c, path) do
    case Req.get("#{c.url}#{path}", receive_timeout: @http_timeout) do
      {:ok, %{status: 200, body: b}} -> {:ok, b}
      {:ok, %{status: s, body: b}} -> {:error, "HTTP #{s}: #{inspect(b)}"}
      {:error, reason} -> {:error, reason}
    end
  end

  # --- message handler ---

  defp handle_msg(msg, c) do
    from = msg["from"] || "unknown"
    subject = msg["subject"] || "(no subject)"
    msg_type = msg["type"] || "info"
    msg_id = msg["id"]

    Logger.info("[MQ] Received #{msg_type} from #{from}: #{subject}")
    if msg_id, do: do_ack(c, msg_id, "read")
  end

  # --- util ---

  defp schedule(msg, ms), do: Process.send_after(self(), msg, ms)
  defp parse_int(nil, d), do: d
  defp parse_int(s, d), do: (case Integer.parse(s) do {v, _} -> v; :error -> d end)
  defp parse_caps(""), do: []
  defp parse_caps(s), do: s |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
end
