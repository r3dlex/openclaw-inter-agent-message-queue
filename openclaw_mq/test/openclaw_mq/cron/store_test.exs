defmodule OpenclawMq.Cron.StoreTest do
  use ExUnit.Case, async: false

  alias OpenclawMq.Cron.{Entry, Store}

  # Clear ETS table before each test
  setup do
    Store.init()
    # Delete all entries
    :ets.delete_all_objects(:cron_entries)
    :ok
  end

  defp make_entry(overrides \\ %{}) do
    base = %{
      "agent_id" => "test_agent",
      "name" => "job_#{:erlang.unique_integer([:positive])}",
      "expression" => "0 * * * *"
    }

    {:ok, entry} = Entry.from_params(Map.merge(base, overrides))
    entry
  end

  describe "put/1 and get/1" do
    test "put stores an entry, get retrieves it by id" do
      entry = make_entry()
      :ok = Store.put(entry)
      assert {:ok, ^entry} = Store.get(entry.id)
    end

    test "get returns {:error, :not_found} for unknown id" do
      assert {:error, :not_found} = Store.get("nonexistent-id")
    end

    test "duplicate put overwrites (idempotent)" do
      entry = make_entry()
      :ok = Store.put(entry)
      updated = %{entry | enabled: false}
      :ok = Store.put(updated)
      assert {:ok, got} = Store.get(entry.id)
      assert got.enabled == false
    end
  end

  describe "list/0" do
    test "returns empty list when no entries" do
      assert Store.list() == []
    end

    test "returns all stored entries" do
      e1 = make_entry(%{"agent_id" => "agent_a"})
      e2 = make_entry(%{"agent_id" => "agent_b"})
      Store.put(e1)
      Store.put(e2)
      all = Store.list()
      assert length(all) == 2
      ids = Enum.map(all, & &1.id)
      assert e1.id in ids
      assert e2.id in ids
    end
  end

  describe "list_for_agent/1" do
    test "returns only entries belonging to the given agent_id" do
      e1 = make_entry(%{"agent_id" => "agent_x"})
      e2 = make_entry(%{"agent_id" => "agent_x"})
      e3 = make_entry(%{"agent_id" => "agent_y"})
      Store.put(e1)
      Store.put(e2)
      Store.put(e3)

      result = Store.list_for_agent("agent_x")
      assert length(result) == 2
      assert Enum.all?(result, &(&1.agent_id == "agent_x"))
    end

    test "returns empty list when agent has no crons" do
      assert Store.list_for_agent("ghost_agent") == []
    end
  end

  describe "update/2" do
    test "modifies a field and returns {:ok, updated_entry}" do
      entry = make_entry()
      Store.put(entry)

      assert {:ok, updated} = Store.update(entry.id, %{"enabled" => false})
      assert updated.enabled == false
      assert {:ok, fetched} = Store.get(entry.id)
      assert fetched.enabled == false
    end

    test "returns {:error, :not_found} for unknown id" do
      assert {:error, :not_found} = Store.update("no-such-id", %{"enabled" => false})
    end

    test "updates last_fired_at" do
      entry = make_entry()
      Store.put(entry)
      now = DateTime.utc_now()
      assert {:ok, updated} = Store.update(entry.id, %{"last_fired_at" => now})
      assert updated.last_fired_at == now
    end
  end

  describe "delete/1" do
    test "removes entry; subsequent get returns {:error, :not_found}" do
      entry = make_entry()
      Store.put(entry)
      :ok = Store.delete(entry.id)
      assert {:error, :not_found} = Store.get(entry.id)
    end

    test "returns {:error, :not_found} when deleting unknown id" do
      assert {:error, :not_found} = Store.delete("nonexistent-id")
    end
  end

  describe "update/2 — unknown fields are ignored" do
    test "unknown field key is silently ignored, other fields unaffected" do
      entry = make_entry()
      Store.put(entry)
      # "unknown_key" is not a known field — should be ignored (covers the `_ -> acc` clause)
      assert {:ok, updated} = Store.update(entry.id, %{"unknown_key" => "value"})
      assert updated.name == entry.name
      assert updated.enabled == entry.enabled
    end
  end

  describe "DETS persistence" do
    test "init/0 and put/1 work with DETS enabled using a temp path" do
      tmp_path = "/tmp/cron_test_#{:erlang.unique_integer([:positive])}.dets"

      try do
        Application.put_env(:openclaw_mq, :cron_dets_enabled, true)
        Application.put_env(:openclaw_mq, :cron_dets_path, tmp_path)

        # Re-init with DETS enabled — should load (empty) from new file
        :ets.delete_all_objects(:cron_entries)
        Store.init()

        entry = make_entry()
        Store.put(entry)
        assert {:ok, _} = Store.get(entry.id)
      after
        Application.put_env(:openclaw_mq, :cron_dets_enabled, false)
        File.rm(tmp_path)
      end
    end

    test "load_from_dets handles DETS open error gracefully" do
      # Using an invalid (directory) path triggers a DETS open error
      Application.put_env(:openclaw_mq, :cron_dets_enabled, true)
      Application.put_env(:openclaw_mq, :cron_dets_path, "/tmp")

      :ets.delete_all_objects(:cron_entries)
      # Should not raise — just logs a warning
      assert :ok = Store.init()

      Application.put_env(:openclaw_mq, :cron_dets_enabled, false)
    end
  end
end
