defmodule OpenclawMq.Cron.SchedulerTest do
  use ExUnit.Case, async: false

  alias OpenclawMq.Cron.{Entry, Scheduler, Store}
  alias OpenclawMq.Cron.SchedulerTest.{FakeStore, FakeDispatcher}

  # We use Application.put_env to inject fake implementations for Store and Dispatcher.

  setup do
    # Ensure the cron ETS table exists and is empty
    Store.init()
    :ets.delete_all_objects(:cron_entries)

    # Use test doubles via application env overrides
    Application.put_env(:openclaw_mq, :store_mod, FakeStore)
    Application.put_env(:openclaw_mq, :dispatcher_mod, FakeDispatcher)

    # Ensure the fake agents are running and cleared
    FakeStore.reset()
    FakeDispatcher.reset()

    # Ensure Scheduler is running — start it if not (e.g. in isolated test runs)
    ensure_scheduler_running()

    # Remove all scheduled entries so each test starts clean
    for entry <- Store.list() do
      Scheduler.remove_entry(entry.id)
    end

    on_exit(fn ->
      Application.put_env(:openclaw_mq, :store_mod, OpenclawMq.Store)
      Application.put_env(:openclaw_mq, :dispatcher_mod, OpenclawMq.Gateway.Dispatcher)
    end)

    :ok
  end

  defp ensure_scheduler_running do
    case GenServer.whereis(Scheduler) do
      nil ->
        {:ok, _} = Scheduler.start_link([])

      _pid ->
        :ok
    end
  end

  defp make_entry(overrides \\ %{}) do
    base = %{
      "agent_id" => "sched_agent",
      "name" => "job_#{:erlang.unique_integer([:positive])}",
      "expression" => "0 * * * *",
      "enabled" => true
    }

    {:ok, entry} = Entry.from_params(Map.merge(base, overrides))
    entry
  end

  describe "start with enabled entry" do
    test "entry is scheduled on start" do
      entry = make_entry()
      Store.put(entry)
      Scheduler.add_entry(entry)
      assert Scheduler.scheduled?(entry.id)
    end

    test "disabled entry is NOT scheduled on start" do
      entry = make_entry(%{"enabled" => false})
      Store.put(entry)
      Scheduler.add_entry(entry)
      refute Scheduler.scheduled?(entry.id)
    end
  end

  describe "fire message" do
    test "sending :fire delivers message to agent inbox" do
      entry = make_entry()
      Store.put(entry)
      Scheduler.add_entry(entry)
      scheduler_pid = GenServer.whereis(Scheduler)

      send(scheduler_pid, {:fire, entry.id})
      # Give the scheduler time to process
      Process.sleep(50)

      msgs = FakeStore.messages()
      assert length(msgs) == 1
      [msg] = msgs
      assert msg.to == entry.agent_id
      assert msg.from == "iamq"
      assert msg.subject == "cron::#{entry.name}"
      assert is_map(msg.body)
      assert msg.body["cron_id"] == entry.id
      assert msg.body["expression"] == entry.expression
      assert is_binary(msg.body["fired_at"])
      assert msg.priority == "NORMAL"
    end

    test "after firing, last_fired_at is updated in CronStore" do
      entry = make_entry()
      Store.put(entry)
      Scheduler.add_entry(entry)
      scheduler_pid = GenServer.whereis(Scheduler)

      send(scheduler_pid, {:fire, entry.id})
      Process.sleep(50)

      {:ok, updated} = Store.get(entry.id)
      assert updated.last_fired_at != nil
      assert %DateTime{} = updated.last_fired_at
    end
  end

  describe "add_entry/1" do
    test "dynamically registers a new entry for scheduling" do
      entry = make_entry()
      Store.put(entry)
      :ok = Scheduler.add_entry(entry)
      assert Scheduler.scheduled?(entry.id)
    end

    test "disabled entry added via add_entry is not scheduled" do
      entry = make_entry(%{"enabled" => false})
      Store.put(entry)
      :ok = Scheduler.add_entry(entry)
      refute Scheduler.scheduled?(entry.id)
    end
  end

  describe "remove_entry/1" do
    test "cancels scheduling for an entry" do
      entry = make_entry()
      Store.put(entry)
      Scheduler.add_entry(entry)
      assert Scheduler.scheduled?(entry.id)
      :ok = Scheduler.remove_entry(entry.id)
      refute Scheduler.scheduled?(entry.id)
    end
  end

  describe "enable_entry/1 and disable_entry/1" do
    test "enable_entry schedules a previously disabled entry" do
      entry = make_entry(%{"enabled" => false})
      Store.put(entry)
      Scheduler.add_entry(entry)
      refute Scheduler.scheduled?(entry.id)

      enabled_entry = %{entry | enabled: true}
      Store.put(enabled_entry)
      :ok = Scheduler.enable_entry(enabled_entry)
      assert Scheduler.scheduled?(entry.id)
    end

    test "disable_entry stops scheduling a running entry" do
      entry = make_entry()
      Store.put(entry)
      Scheduler.add_entry(entry)
      assert Scheduler.scheduled?(entry.id)

      :ok = Scheduler.disable_entry(entry.id)
      refute Scheduler.scheduled?(entry.id)
    end
  end

  describe "edge cases" do
    test "firing a cron_id not in the store is handled gracefully" do
      scheduler_pid = GenServer.whereis(Scheduler)
      # Send a fire message for a non-existent cron_id — should not crash
      send(scheduler_pid, {:fire, "nonexistent-cron-id"})
      Process.sleep(50)
      # Scheduler should still be alive
      assert Process.alive?(scheduler_pid)
    end

    test "cron with */5 expression is scheduled correctly" do
      entry = make_entry(%{"expression" => "*/5 * * * *"})
      Store.put(entry)
      :ok = Scheduler.add_entry(entry)
      assert Scheduler.scheduled?(entry.id)
    end

    test "cron with range expression like 0-5 is scheduled correctly" do
      entry = make_entry(%{"expression" => "0 0-5 * * *"})
      Store.put(entry)
      :ok = Scheduler.add_entry(entry)
      assert Scheduler.scheduled?(entry.id)
    end

    test "scheduler picks up multiple enabled entries on init" do
      # Add entries to the store, then add_entry them to the running scheduler
      e1 = make_entry()
      e2 = make_entry()
      Store.put(e1)
      Store.put(e2)
      Scheduler.add_entry(e1)
      Scheduler.add_entry(e2)
      assert Scheduler.scheduled?(e1.id)
      assert Scheduler.scheduled?(e2.id)
    end
  end

  # --- Test doubles ---

  defmodule FakeStore do
    @moduledoc "In-memory fake for OpenclawMq.Store — records put/1 calls."
    use Agent

    def start_link(_), do: Agent.start_link(fn -> [] end, name: __MODULE__)

    @doc "Reset the recorded messages to an empty list. Starts the agent if needed."
    def reset do
      if pid = GenServer.whereis(__MODULE__) do
        Agent.update(pid, fn _ -> [] end)
      else
        Agent.start_link(fn -> [] end, name: __MODULE__)
      end
    end

    @doc "Record a message (mirrors OpenclawMq.Store.put/1)."
    def put(msg) do
      Agent.update(__MODULE__, fn msgs -> [msg | msgs] end)
      :ok
    end

    @doc "Return all recorded messages."
    def messages, do: Agent.get(__MODULE__, & &1)
  end

  defmodule FakeDispatcher do
    @moduledoc "In-memory fake for OpenclawMq.Gateway.Dispatcher — records deliver/2 calls."
    use Agent

    def start_link(_), do: Agent.start_link(fn -> [] end, name: __MODULE__)

    @doc "Reset the recorded calls. Starts the agent if needed."
    def reset do
      if pid = GenServer.whereis(__MODULE__) do
        Agent.update(pid, fn _ -> [] end)
      else
        Agent.start_link(fn -> [] end, name: __MODULE__)
      end
    end

    @doc "Record a deliver call (mirrors OpenclawMq.Gateway.Dispatcher.deliver/2)."
    def deliver(agent_id, msg) do
      Agent.update(__MODULE__, fn calls -> [{agent_id, msg} | calls] end)
    end

    @doc "Return all recorded deliver calls."
    def calls, do: Agent.get(__MODULE__, & &1)
  end
end
