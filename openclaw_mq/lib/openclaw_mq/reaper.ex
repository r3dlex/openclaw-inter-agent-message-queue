defmodule OpenclawMq.Reaper do
  @moduledoc """
  Periodic cleanup process.
  - Reaps stale agents from the registry.
  - Purges expired messages.
  - Purges old acted/archived messages (>7 days).
  """
  use GenServer

  require Logger

  @seven_days_ms 7 * 24 * 60 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    interval = Application.get_env(:openclaw_mq, :reap_interval_ms, 60_000)
    Process.send_after(self(), :reap, interval)
    {:ok, %{interval: interval}}
  end

  @impl true
  def handle_info(:reap, state) do
    ttl = Application.get_env(:openclaw_mq, :agent_ttl_ms, 300_000)

    # Reap stale agents
    stale = OpenclawMq.Registry.reap_stale(ttl)

    if stale != [] do
      Logger.info("[Reaper] Reaped stale agents: #{inspect(stale)}")
    end

    # Purge expired messages
    OpenclawMq.Store.purge_expired()

    # Purge old acted/archived messages
    OpenclawMq.Store.purge_old(@seven_days_ms)

    Process.send_after(self(), :reap, state.interval)
    {:noreply, state}
  end
end
