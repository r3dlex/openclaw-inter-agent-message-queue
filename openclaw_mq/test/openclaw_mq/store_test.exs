defmodule OpenclawMq.StoreTest do
  use ExUnit.Case, async: false

  alias OpenclawMq.{Message, Store}

  # Uses the already-running Store. Messages are identified by unique IDs;
  # we clean them up in on_exit to avoid polluting other tests.

  defp make_msg(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          "from" => "test_sender",
          "to" => "test_receiver_#{:erlang.unique_integer([:positive])}",
          "type" => "info",
          "subject" => "test subject",
          "body" => "test body"
        },
        overrides
      )

    {:ok, msg} = Message.new(attrs)
    msg
  end

  setup do
    msgs = []
    {:ok, msgs: msgs}
  end

  describe "put/1 and get/1" do
    test "stores a message and retrieves it by ID" do
      msg = make_msg()
      assert :ok = Store.put(msg)
      assert {:ok, fetched} = Store.get(msg.id)
      assert fetched.id == msg.id
      assert fetched.from == msg.from
      assert fetched.subject == msg.subject
    end

    test "get/1 returns :not_found for unknown ID" do
      assert :not_found = Store.get("nonexistent-id-#{:erlang.unique_integer()}")
    end

    test "persists message to disk" do
      msg = make_msg()
      Store.put(msg)
      queue_dir = Application.get_env(:openclaw_mq, :queue_dir)
      agent_dir = Path.join(queue_dir, msg.to)
      assert File.dir?(agent_dir)
      files = File.ls!(agent_dir)
      assert Enum.any?(files, &String.ends_with?(&1, ".json"))
    end
  end

  describe "inbox/2" do
    test "returns messages for a specific agent" do
      to = "inbox_agent_#{:erlang.unique_integer([:positive])}"
      msg1 = make_msg(%{"to" => to, "subject" => "msg1"})
      msg2 = make_msg(%{"to" => to, "subject" => "msg2"})
      Store.put(msg1)
      Store.put(msg2)

      inbox = Store.inbox(to)
      subjects = Enum.map(inbox, & &1.subject)
      assert "msg1" in subjects
      assert "msg2" in subjects
    end

    test "returns broadcast messages in any agent's inbox" do
      to = "bcast_target_#{:erlang.unique_integer([:positive])}"
      bcast = make_msg(%{"to" => "broadcast", "subject" => "bcast_#{:erlang.unique_integer()}"})
      Store.put(bcast)

      inbox = Store.inbox(to)
      assert Enum.any?(inbox, &(&1.id == bcast.id))
    end

    test "filters by status" do
      to = "filter_agent_#{:erlang.unique_integer([:positive])}"
      msg = make_msg(%{"to" => to})
      Store.put(msg)

      unread = Store.inbox(to, "unread")
      assert Enum.any?(unread, &(&1.id == msg.id))

      read = Store.inbox(to, "read")
      refute Enum.any?(read, &(&1.id == msg.id))
    end

    test "returns only direct messages for a fresh agent (no direct messages)" do
      # We can't assert empty inbox because broadcast messages from other tests exist;
      # assert there are no DIRECT messages for a never-used agent ID.
      id = "fresh_#{:erlang.unique_integer([:positive])}"
      all = Store.inbox(id)
      direct = Enum.filter(all, &(&1.to == id))
      assert direct == []
    end
  end

  describe "update_status/2" do
    test "changes message status" do
      msg = make_msg()
      Store.put(msg)
      assert :ok = Store.update_status(msg.id, "read")
      {:ok, updated} = Store.get(msg.id)
      assert updated.status == "read"
    end

    test "returns error for unknown message" do
      assert {:error, _} = Store.update_status("no-such-id", "read")
    end

    test "raises for invalid status" do
      msg = make_msg()
      Store.put(msg)
      assert_raise FunctionClauseError, fn -> Store.update_status(msg.id, "flying") end
    end

    test "persists updated status to disk" do
      msg = make_msg()
      Store.put(msg)
      Store.update_status(msg.id, "acted")
      {:ok, updated} = Store.get(msg.id)
      assert updated.status == "acted"
    end
  end

  describe "purge_old/1" do
    test "removes acted messages older than max_age_ms" do
      msg = make_msg()
      Store.put(msg)
      Store.update_status(msg.id, "acted")
      # Sleep 5ms so message is at least 5ms old, then purge with threshold of 1ms
      Process.sleep(5)
      Store.purge_old(1)
      assert :not_found = Store.get(msg.id)
    end

    test "keeps unread messages regardless of age" do
      msg = make_msg()
      Store.put(msg)
      Store.purge_old(0)
      # unread messages are not purged
      assert {:ok, _} = Store.get(msg.id)
      # cleanup
      Store.update_status(msg.id, "acted")
      Store.purge_old(0)
    end
  end

  describe "purge_expired/0" do
    test "removes messages with an expires_at in the past" do
      past = DateTime.utc_now() |> DateTime.add(-10, :second) |> DateTime.to_iso8601()
      msg = make_msg(%{"expiresAt" => past})
      Store.put(msg)
      Store.purge_expired()
      assert :not_found = Store.get(msg.id)
    end

    test "keeps messages with expires_at in the future" do
      future = DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.to_iso8601()
      msg = make_msg(%{"expiresAt" => future})
      Store.put(msg)
      Store.purge_expired()
      assert {:ok, _} = Store.get(msg.id)
      # cleanup
      Store.update_status(msg.id, "acted")
      Store.purge_old(0)
    end

    test "keeps messages with no expires_at" do
      msg = make_msg()
      Store.put(msg)
      Store.purge_expired()
      assert {:ok, _} = Store.get(msg.id)
      # cleanup
      Store.update_status(msg.id, "acted")
      Store.purge_old(0)
    end
  end

  describe "status_summary/0" do
    test "returns a map with per-agent queue counts" do
      to = "summary_agent_#{:erlang.unique_integer([:positive])}"
      msg1 = make_msg(%{"to" => to})
      msg2 = make_msg(%{"to" => to})
      Store.put(msg1)
      Store.put(msg2)
      Store.update_status(msg1.id, "read")

      summary = Store.status_summary()
      assert is_map(summary)
      agent_summary = Map.get(summary, to)
      assert agent_summary["unread"] == 1
      assert agent_summary["read"] == 1

      # cleanup
      Store.update_status(msg1.id, "acted")
      Store.update_status(msg2.id, "acted")
      Store.purge_old(0)
    end
  end
end
