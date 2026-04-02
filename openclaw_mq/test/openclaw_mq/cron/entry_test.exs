defmodule OpenclawMq.Cron.EntryTest do
  use ExUnit.Case, async: true

  alias OpenclawMq.Cron.Entry

  describe "from_params/1 — valid params" do
    test "returns {:ok, %Entry{}} with all expected fields" do
      params = %{
        "agent_id" => "mail_agent",
        "name" => "tidy_inbox",
        "expression" => "30 6 * * *",
        "enabled" => true
      }

      assert {:ok, entry} = Entry.from_params(params)
      assert %Entry{} = entry
      assert is_binary(entry.id)
      assert entry.agent_id == "mail_agent"
      assert entry.name == "tidy_inbox"
      assert entry.expression == "30 6 * * *"
      assert entry.enabled == true
      assert %DateTime{} = entry.created_at
      assert entry.last_fired_at == nil
    end

    test "generates a UUID as id" do
      params = %{"agent_id" => "a", "name" => "b", "expression" => "0 * * * *"}
      {:ok, e1} = Entry.from_params(params)
      {:ok, e2} = Entry.from_params(params)
      assert e1.id != e2.id
    end

    test "with enabled: false sets enabled to false" do
      params = %{
        "agent_id" => "mail_agent",
        "name" => "quiet_job",
        "expression" => "0 0 * * *",
        "enabled" => false
      }

      assert {:ok, entry} = Entry.from_params(params)
      assert entry.enabled == false
    end

    test "defaults enabled to true when not provided" do
      params = %{"agent_id" => "a", "name" => "b", "expression" => "0 * * * *"}
      assert {:ok, entry} = Entry.from_params(params)
      assert entry.enabled == true
    end
  end

  describe "from_params/1 — invalid params" do
    test "missing agent_id returns {:error, reason}" do
      params = %{"name" => "tidy_inbox", "expression" => "30 6 * * *"}
      assert {:error, reason} = Entry.from_params(params)
      assert is_binary(reason)
    end

    test "missing name returns {:error, reason}" do
      params = %{"agent_id" => "mail_agent", "expression" => "30 6 * * *"}
      assert {:error, reason} = Entry.from_params(params)
      assert is_binary(reason)
    end

    test "missing expression returns {:error, reason}" do
      params = %{"agent_id" => "mail_agent", "name" => "tidy_inbox"}
      assert {:error, reason} = Entry.from_params(params)
      assert is_binary(reason)
    end

    test "invalid cron expression returns {:error, reason}" do
      params = %{
        "agent_id" => "mail_agent",
        "name" => "tidy_inbox",
        "expression" => "not a cron"
      }

      assert {:error, reason} = Entry.from_params(params)
      assert is_binary(reason)
    end

    test "empty expression returns {:error, reason}" do
      params = %{"agent_id" => "mail_agent", "name" => "tidy_inbox", "expression" => ""}
      assert {:error, reason} = Entry.from_params(params)
      assert is_binary(reason)
    end
  end

  describe "valid_expression?/1" do
    test "returns true for '0 8 * * *'" do
      assert Entry.valid_expression?("0 8 * * *") == true
    end

    test "returns true for '30 6 * * *'" do
      assert Entry.valid_expression?("30 6 * * *") == true
    end

    test "returns true for '*/5 * * * *'" do
      assert Entry.valid_expression?("*/5 * * * *") == true
    end

    test "returns false for 'not a cron'" do
      assert Entry.valid_expression?("not a cron") == false
    end

    test "returns false for empty string" do
      assert Entry.valid_expression?("") == false
    end

    test "returns false for nil" do
      assert Entry.valid_expression?(nil) == false
    end
  end

  describe "to_map/1" do
    test "returns all expected keys as strings" do
      {:ok, entry} =
        Entry.from_params(%{
          "agent_id" => "mail_agent",
          "name" => "tidy_inbox",
          "expression" => "30 6 * * *",
          "enabled" => true
        })

      map = Entry.to_map(entry)

      assert is_map(map)
      assert is_binary(map["id"])
      assert map["agent_id"] == "mail_agent"
      assert map["name"] == "tidy_inbox"
      assert map["expression"] == "30 6 * * *"
      assert map["enabled"] == true
      assert is_binary(map["created_at"])
      assert Map.has_key?(map, "last_fired_at")
    end

    test "last_fired_at is nil when never fired" do
      {:ok, entry} =
        Entry.from_params(%{"agent_id" => "a", "name" => "b", "expression" => "0 * * * *"})

      map = Entry.to_map(entry)
      assert map["last_fired_at"] == nil
    end
  end
end
