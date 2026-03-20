defmodule OpenclawMq.Registry do
  @moduledoc """
  Tracks which agents are online and when they last checked in.
  Agents register on session start and heartbeat periodically.
  """
  use GenServer

  require Logger

  # Client API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc "Register an agent as online. Returns :ok."
  def register(agent_id) do
    GenServer.call(__MODULE__, {:register, agent_id})
  end

  @doc "Remove an agent from the registry."
  def unregister(agent_id) do
    GenServer.call(__MODULE__, {:unregister, agent_id})
  end

  @doc "Update heartbeat timestamp for an agent."
  def heartbeat(agent_id) do
    GenServer.call(__MODULE__, {:heartbeat, agent_id})
  end

  @doc "Check if an agent is registered."
  def online?(agent_id) do
    GenServer.call(__MODULE__, {:online?, agent_id})
  end

  @doc "List all registered agents with their last heartbeat."
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
  def handle_call({:register, agent_id}, _from, state) do
    now = System.monotonic_time(:millisecond)
    Logger.info("[Registry] Agent registered: #{agent_id}")

    # Subscribe the agent to its own topic and broadcast
    Phoenix.PubSub.subscribe(OpenclawMq.PubSub, "agent:#{agent_id}")
    Phoenix.PubSub.subscribe(OpenclawMq.PubSub, "broadcast")

    {:reply, :ok, Map.put(state, agent_id, %{registered_at: now, last_heartbeat: now})}
  end

  @impl true
  def handle_call({:unregister, agent_id}, _from, state) do
    Logger.info("[Registry] Agent unregistered: #{agent_id}")
    {:reply, :ok, Map.delete(state, agent_id)}
  end

  @impl true
  def handle_call({:heartbeat, agent_id}, _from, state) do
    now = System.monotonic_time(:millisecond)

    case Map.get(state, agent_id) do
      nil ->
        # Auto-register on heartbeat if not registered
        Logger.info("[Registry] Agent auto-registered via heartbeat: #{agent_id}")
        {:reply, :ok, Map.put(state, agent_id, %{registered_at: now, last_heartbeat: now})}

      info ->
        {:reply, :ok, Map.put(state, agent_id, %{info | last_heartbeat: now})}
    end
  end

  @impl true
  def handle_call({:online?, agent_id}, _from, state) do
    {:reply, Map.has_key?(state, agent_id), state}
  end

  @impl true
  def handle_call(:list, _from, state) do
    agents =
      Enum.map(state, fn {id, info} ->
        %{
          "id" => id,
          "registered_at" => info.registered_at,
          "last_heartbeat" => info.last_heartbeat
        }
      end)

    {:reply, agents, state}
  end

  @impl true
  def handle_call({:reap, ttl_ms}, _from, state) do
    now = System.monotonic_time(:millisecond)
    cutoff = now - ttl_ms

    {stale, alive} =
      Enum.split_with(state, fn {_id, info} ->
        info.last_heartbeat < cutoff
      end)

    for {id, _} <- stale do
      Logger.warn("[Registry] Reaping stale agent: #{id}")
    end

    {:reply, Enum.map(stale, fn {id, _} -> id end), Map.new(alive)}
  end
end
