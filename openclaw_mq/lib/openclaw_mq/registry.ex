defmodule OpenclawMq.Registry do
  @moduledoc """
  Tracks which agents are online, when they last checked in, and their
  discoverable metadata (name, emoji, description, capabilities).

  Agents register on session start and heartbeat periodically. Other agents
  can discover peers via `list_agents/0` or `get_agent/1`.
  """
  use GenServer

  require Logger

  # Client API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Register an agent as online with optional metadata.

  `opts` is an optional map that may include:
    - `"name"` — human-readable display name (e.g. "Librarian 📚")
    - `"emoji"` — single emoji for dashboards (e.g. "📚")
    - `"description"` — what the agent does (e.g. "Document archivist and knowledge organizer")
    - `"capabilities"` — list of capability strings (e.g. ["search", "summarize", "archive"])
    - `"workspace"` — the agent's workspace/repo path
  """
  def register(agent_id, opts \\ %{}) do
    GenServer.call(__MODULE__, {:register, agent_id, opts})
  end

  @doc "Remove an agent from the registry."
  def unregister(agent_id) do
    GenServer.call(__MODULE__, {:unregister, agent_id})
  end

  @doc "Update heartbeat timestamp for an agent."
  def heartbeat(agent_id) do
    GenServer.call(__MODULE__, {:heartbeat, agent_id})
  end

  @doc "Update an agent's metadata without re-registering."
  def update_metadata(agent_id, metadata) do
    GenServer.call(__MODULE__, {:update_metadata, agent_id, metadata})
  end

  @doc "Check if an agent is registered."
  def online?(agent_id) do
    GenServer.call(__MODULE__, {:online?, agent_id})
  end

  @doc "Get a single agent's full profile (metadata + timestamps)."
  def get_agent(agent_id) do
    GenServer.call(__MODULE__, {:get, agent_id})
  end

  @doc "List all registered agents with their metadata and last heartbeat."
  def list_agents do
    GenServer.call(__MODULE__, :list)
  end

  @doc "Remove agents that haven't sent a heartbeat within ttl_ms."
  def reap_stale(ttl_ms) do
    GenServer.call(__MODULE__, {:reap, ttl_ms})
  end

  # Server

  @impl true
  def init(_) do
    {:ok, %{}}
  end

  @impl true
  def handle_call({:register, agent_id, opts}, _from, state) do
    now_mono = System.monotonic_time(:millisecond)
    now_wall = DateTime.utc_now() |> DateTime.to_iso8601()
    Logger.info("[Registry] Agent registered: #{agent_id}")

    # Subscribe the agent to its own topic and broadcast
    Phoenix.PubSub.subscribe(OpenclawMq.PubSub, "agent:#{agent_id}")
    Phoenix.PubSub.subscribe(OpenclawMq.PubSub, "broadcast")

    # Preserve existing metadata if re-registering, merge with new opts
    existing_meta =
      case Map.get(state, agent_id) do
        nil -> %{}
        old -> Map.get(old, :metadata, %{})
      end

    metadata = Map.merge(existing_meta, extract_metadata(opts))

    # Persist metadata to disk so heartbeat auto-register can restore it
    if metadata != %{}, do: persist_metadata(agent_id, metadata)

    entry = %{
      registered_at: now_wall,
      last_heartbeat: now_wall,
      last_heartbeat_mono: now_mono,
      metadata: metadata
    }

    {:reply, :ok, Map.put(state, agent_id, entry)}
  end

  # Backwards-compatible: register/1 calls register/2 with empty opts
  def handle_call({:register, agent_id}, from, state) do
    handle_call({:register, agent_id, %{}}, from, state)
  end

  @impl true
  def handle_call({:unregister, agent_id}, _from, state) do
    Logger.info("[Registry] Agent unregistered: #{agent_id}")
    {:reply, :ok, Map.delete(state, agent_id)}
  end

  @impl true
  def handle_call({:heartbeat, agent_id}, _from, state) do
    now_mono = System.monotonic_time(:millisecond)
    now_wall = DateTime.utc_now() |> DateTime.to_iso8601()

    case Map.get(state, agent_id) do
      nil ->
        # Check if we have persisted metadata from a previous registration
        persisted_meta = load_persisted_metadata(agent_id)

        if persisted_meta != %{} do
          Logger.info(
            "[Registry] Agent auto-registered via heartbeat with persisted metadata: #{agent_id}"
          )
        else
          Logger.info("[Registry] Agent auto-registered via heartbeat: #{agent_id}")
        end

        entry = %{
          registered_at: now_wall,
          last_heartbeat: now_wall,
          last_heartbeat_mono: now_mono,
          metadata: persisted_meta
        }

        {:reply, :ok, Map.put(state, agent_id, entry)}

      info ->
        updated = %{info | last_heartbeat: now_wall, last_heartbeat_mono: now_mono}
        {:reply, :ok, Map.put(state, agent_id, updated)}
    end
  end

  @impl true
  def handle_call({:update_metadata, agent_id, new_meta}, _from, state) do
    case Map.get(state, agent_id) do
      nil ->
        {:reply, {:error, "agent not registered"}, state}

      info ->
        merged = Map.merge(Map.get(info, :metadata, %{}), extract_metadata(new_meta))
        updated = %{info | metadata: merged}
        if merged != %{}, do: persist_metadata(agent_id, merged)
        Logger.info("[Registry] Metadata updated for #{agent_id}: #{inspect(Map.keys(merged))}")
        {:reply, :ok, Map.put(state, agent_id, updated)}
    end
  end

  @impl true
  def handle_call({:online?, agent_id}, _from, state) do
    {:reply, Map.has_key?(state, agent_id), state}
  end

  @impl true
  def handle_call({:get, agent_id}, _from, state) do
    case Map.get(state, agent_id) do
      nil ->
        {:reply, {:error, "not found"}, state}

      info ->
        {:reply, {:ok, format_agent(agent_id, info)}, state}
    end
  end

  @impl true
  def handle_call(:list, _from, state) do
    agents =
      Enum.map(state, fn {id, info} ->
        format_agent(id, info)
      end)

    {:reply, agents, state}
  end

  @impl true
  def handle_call({:reap, ttl_ms}, _from, state) do
    now = System.monotonic_time(:millisecond)
    cutoff = now - ttl_ms

    {stale, alive} =
      Enum.split_with(state, fn {_id, info} ->
        info.last_heartbeat_mono < cutoff
      end)

    for {id, _} <- stale do
      Logger.warning("[Registry] Reaping stale agent: #{id}")
    end

    {:reply, Enum.map(stale, fn {id, _} -> id end), Map.new(alive)}
  end

  # Helpers

  @metadata_keys ~w(name emoji description capabilities workspace)

  defp extract_metadata(opts) when is_map(opts) do
    opts
    |> Map.take(@metadata_keys)
    |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
    |> Map.new()
  end

  defp extract_metadata(_), do: %{}

  defp format_agent(id, info) do
    base = %{
      "id" => id,
      "registered_at" => info.registered_at,
      "last_heartbeat" => info.last_heartbeat
    }

    meta = Map.get(info, :metadata, %{})

    base
    |> maybe_put("name", Map.get(meta, "name"))
    |> maybe_put("emoji", Map.get(meta, "emoji"))
    |> maybe_put("description", Map.get(meta, "description"))
    |> maybe_put("capabilities", Map.get(meta, "capabilities"))
    |> maybe_put("workspace", Map.get(meta, "workspace"))
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, _key, []), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  # --- Metadata persistence ---

  defp metadata_dir do
    queue_dir = Application.get_env(:openclaw_mq, :queue_dir, "queue")
    Path.join(queue_dir, ".metadata")
  end

  defp metadata_path(agent_id) do
    Path.join(metadata_dir(), "#{agent_id}.json")
  end

  defp persist_metadata(agent_id, metadata) do
    dir = metadata_dir()
    File.mkdir_p!(dir)
    path = metadata_path(agent_id)
    json = Jason.encode!(metadata, pretty: true)

    case File.write(path, json) do
      :ok ->
        Logger.debug("[Registry] Persisted metadata for #{agent_id}")
        :ok

      {:error, reason} ->
        Logger.warning(
          "[Registry] Failed to persist metadata for #{agent_id}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  defp load_persisted_metadata(agent_id) do
    path = metadata_path(agent_id)

    case File.read(path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, meta} when is_map(meta) -> meta
          _ -> %{}
        end

      {:error, _} ->
        %{}
    end
  end
end
