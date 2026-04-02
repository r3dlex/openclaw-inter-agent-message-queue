defmodule OpenclawMq.Cron.Scheduler do
  @moduledoc """
  GenServer that manages firing of registered cron schedules.

  On start, loads all enabled entries from `OpenclawMq.Cron.Store` and schedules
  each one using `Process.send_after/3` based on the next UTC firing time computed
  by `Crontab.Scheduler.get_next_run_date!/2`.

  When a cron fires:
    1. Builds a message and stores it via the configured store module.
    2. Triggers delivery via the configured dispatcher module.
    3. Updates `:last_fired_at` in `OpenclawMq.Cron.Store`.
    4. Schedules the next firing.

  Accepts dynamic management via `add_entry/1`, `remove_entry/1`,
  `enable_entry/1`, and `disable_entry/1`.

  Dependencies (`OpenclawMq.Store` and `OpenclawMq.Gateway.Dispatcher`) can be
  overridden for testing via `Application.put_env/3`:
    - `:openclaw_mq, :store_mod` — defaults to `OpenclawMq.Store`
    - `:openclaw_mq, :dispatcher_mod` — defaults to `OpenclawMq.Gateway.Dispatcher`
  """

  use GenServer

  require Logger

  alias OpenclawMq.Cron.{Entry, Store}
  alias OpenclawMq.Message

  # State: %{cron_id => timer_ref}
  defstruct timers: %{}

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Add and schedule a new cron entry dynamically."
  @spec add_entry(Entry.t()) :: :ok
  def add_entry(%Entry{} = entry) do
    GenServer.call(__MODULE__, {:add_entry, entry})
  end

  @doc "Cancel and remove a cron entry by ID."
  @spec remove_entry(String.t()) :: :ok
  def remove_entry(id) do
    GenServer.call(__MODULE__, {:remove_entry, id})
  end

  @doc "Enable a cron entry and schedule it."
  @spec enable_entry(Entry.t()) :: :ok
  def enable_entry(%Entry{} = entry) do
    GenServer.call(__MODULE__, {:enable_entry, entry})
  end

  @doc "Disable a cron entry and cancel its timer."
  @spec disable_entry(String.t()) :: :ok
  def disable_entry(id) do
    GenServer.call(__MODULE__, {:disable_entry, id})
  end

  @doc "Check whether a cron entry is currently scheduled."
  @spec scheduled?(String.t()) :: boolean()
  def scheduled?(id) do
    GenServer.call(__MODULE__, {:scheduled?, id})
  end

  # --- GenServer callbacks ---

  @impl true
  def init(_opts) do
    state = %__MODULE__{}
    Store.init()

    enabled_entries =
      Store.list()
      |> Enum.filter(& &1.enabled)

    state =
      Enum.reduce(enabled_entries, state, fn entry, acc ->
        schedule_entry(entry, acc)
      end)

    Logger.info("[Cron.Scheduler] Started. Scheduled #{map_size(state.timers)} cron(s).")
    {:ok, state}
  end

  @impl true
  def handle_call({:add_entry, entry}, _from, state) do
    new_state =
      if entry.enabled do
        schedule_entry(entry, state)
      else
        state
      end

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:remove_entry, id}, _from, state) do
    new_state = cancel_timer(id, state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:enable_entry, entry}, _from, state) do
    new_state = schedule_entry(entry, state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:disable_entry, id}, _from, state) do
    new_state = cancel_timer(id, state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:scheduled?, id}, _from, state) do
    {:reply, Map.has_key?(state.timers, id), state}
  end

  @impl true
  def handle_info({:fire, cron_id}, state) do
    new_state =
      case Store.get(cron_id) do
        {:ok, entry} ->
          fire_entry(entry)

          # Re-schedule next firing
          state_without = %{state | timers: Map.delete(state.timers, cron_id)}

          if entry.enabled do
            schedule_entry(entry, state_without)
          else
            state_without
          end

        {:error, :not_found} ->
          Logger.warning(
            "[Cron.Scheduler] Fired cron_id=#{cron_id} not found in store, skipping."
          )

          %{state | timers: Map.delete(state.timers, cron_id)}
      end

    {:noreply, new_state}
  end

  # --- Private helpers ---

  defp schedule_entry(%Entry{id: id, expression: expression} = entry, state) do
    # Cancel existing timer if any
    state = cancel_timer(id, state)

    case next_fire_ms(expression) do
      {:ok, ms} ->
        ref = Process.send_after(self(), {:fire, id}, ms)
        Logger.info("[Cron.Scheduler] Scheduled cron=#{entry.name} id=#{id} fires_in=#{ms}ms")
        %{state | timers: Map.put(state.timers, id, ref)}

      {:error, reason} ->
        Logger.warning(
          "[Cron.Scheduler] Could not schedule cron=#{entry.name} id=#{id}: #{inspect(reason)}"
        )

        state
    end
  end

  defp cancel_timer(id, state) do
    case Map.get(state.timers, id) do
      nil ->
        state

      ref ->
        Process.cancel_timer(ref)
        %{state | timers: Map.delete(state.timers, id)}
    end
  end

  defp next_fire_ms(expression) do
    try do
      {:ok, cron_expr} = Crontab.CronExpression.Parser.parse(expression)
      now = NaiveDateTime.utc_now()
      next = Crontab.Scheduler.get_next_run_date!(cron_expr, now)
      diff_seconds = NaiveDateTime.diff(next, now, :second)
      ms = max(diff_seconds * 1_000, 0)
      {:ok, ms}
    rescue
      e -> {:error, inspect(e)}
    end
  end

  defp fire_entry(%Entry{} = entry) do
    fired_at = DateTime.utc_now()

    msg_params = %{
      "from" => "iamq",
      "to" => entry.agent_id,
      "type" => "info",
      "subject" => "cron::#{entry.name}",
      "body" => %{
        "fired_at" => DateTime.to_iso8601(fired_at),
        "expression" => entry.expression,
        "cron_id" => entry.id
      },
      "priority" => "NORMAL"
    }

    case Message.new(msg_params) do
      {:ok, msg} ->
        store_mod = Application.get_env(:openclaw_mq, :store_mod, OpenclawMq.Store)

        dispatcher_mod =
          Application.get_env(:openclaw_mq, :dispatcher_mod, OpenclawMq.Gateway.Dispatcher)

        store_mod.put(msg)
        dispatcher_mod.deliver(entry.agent_id, msg)

        Store.update(entry.id, %{"last_fired_at" => fired_at})

        Logger.info(
          "[Cron.Scheduler] Fired cron=#{entry.name} id=#{entry.id} agent=#{entry.agent_id}"
        )

      {:error, reason} ->
        Logger.warning(
          "[Cron.Scheduler] Failed to build message for cron=#{entry.name}: #{inspect(reason)}"
        )
    end
  end
end
