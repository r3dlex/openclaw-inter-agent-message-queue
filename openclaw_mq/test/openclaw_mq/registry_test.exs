defmodule OpenclawMq.RegistryTest do
  use ExUnit.Case, async: false

  # Uses the already-running Registry started by the application.
  # All agent IDs are unique per test to avoid interference.

  setup do
    # Generate a unique prefix for this test's agent IDs
    prefix = "test_#{:erlang.unique_integer([:positive])}"

    on_exit(fn ->
      # Clean up all agents registered by this test
      for i <- 1..5 do
        OpenclawMq.Registry.unregister("#{prefix}_#{i}")
      end

      OpenclawMq.Registry.unregister("#{prefix}")
    end)

    {:ok, prefix: prefix}
  end

  describe "register/2" do
    test "registers an agent with no metadata", %{prefix: p} do
      id = "#{p}_1"
      assert :ok = OpenclawMq.Registry.register(id)
      assert OpenclawMq.Registry.online?(id)
    end

    test "registers an agent with metadata", %{prefix: p} do
      id = "#{p}_1"

      assert :ok =
               OpenclawMq.Registry.register(id, %{
                 "name" => "Test Agent",
                 "emoji" => "🧪",
                 "description" => "test agent",
                 "capabilities" => ["test"],
                 "workspace" => "/tmp/test"
               })

      {:ok, agent} = OpenclawMq.Registry.get_agent(id)
      assert agent["name"] == "Test Agent"
      assert agent["emoji"] == "🧪"
      assert agent["description"] == "test agent"
      assert agent["capabilities"] == ["test"]
      assert agent["workspace"] == "/tmp/test"
    end

    test "re-registering merges metadata", %{prefix: p} do
      id = "#{p}_1"
      OpenclawMq.Registry.register(id, %{"name" => "Old Name", "emoji" => "🤖"})
      OpenclawMq.Registry.register(id, %{"name" => "New Name"})
      {:ok, agent} = OpenclawMq.Registry.get_agent(id)
      # emoji preserved from first registration; name overwritten
      assert agent["name"] == "New Name"
      assert agent["emoji"] == "🤖"
    end

    test "ignores nil and empty string metadata values", %{prefix: p} do
      id = "#{p}_1"
      OpenclawMq.Registry.register(id, %{"name" => nil, "emoji" => "", "description" => "ok"})
      {:ok, agent} = OpenclawMq.Registry.get_agent(id)
      refute Map.has_key?(agent, "name")
      refute Map.has_key?(agent, "emoji")
      assert agent["description"] == "ok"
    end
  end

  describe "unregister/1" do
    test "removes a registered agent", %{prefix: p} do
      id = "#{p}_1"
      OpenclawMq.Registry.register(id)
      assert OpenclawMq.Registry.online?(id)
      assert :ok = OpenclawMq.Registry.unregister(id)
      refute OpenclawMq.Registry.online?(id)
    end

    test "unregistering an unknown agent is a no-op", %{prefix: p} do
      assert :ok = OpenclawMq.Registry.unregister("#{p}_never_registered")
    end
  end

  describe "heartbeat/1" do
    test "updates last_heartbeat for a known agent", %{prefix: p} do
      id = "#{p}_1"
      OpenclawMq.Registry.register(id)
      {:ok, before} = OpenclawMq.Registry.get_agent(id)

      # Small sleep to guarantee timestamp difference
      Process.sleep(10)
      OpenclawMq.Registry.heartbeat(id)

      {:ok, after_hb} = OpenclawMq.Registry.get_agent(id)
      assert after_hb["last_heartbeat"] >= before["last_heartbeat"]
    end

    test "auto-registers an unknown agent via heartbeat", %{prefix: p} do
      id = "#{p}_auto"
      refute OpenclawMq.Registry.online?(id)
      assert :ok = OpenclawMq.Registry.heartbeat(id)
      assert OpenclawMq.Registry.online?(id)
      OpenclawMq.Registry.unregister(id)
    end
  end

  describe "update_metadata/2" do
    test "merges new metadata into existing", %{prefix: p} do
      id = "#{p}_1"
      OpenclawMq.Registry.register(id, %{"name" => "Alpha", "emoji" => "🅰️"})

      assert :ok =
               OpenclawMq.Registry.update_metadata(id, %{"name" => "Beta", "workspace" => "/x"})

      {:ok, agent} = OpenclawMq.Registry.get_agent(id)
      assert agent["name"] == "Beta"
      assert agent["emoji"] == "🅰️"
      assert agent["workspace"] == "/x"
    end

    test "returns error for unknown agent", %{prefix: p} do
      assert {:error, _} = OpenclawMq.Registry.update_metadata("#{p}_ghost", %{"name" => "x"})
    end
  end

  describe "get_agent/1" do
    test "returns agent info with expected fields", %{prefix: p} do
      id = "#{p}_1"
      OpenclawMq.Registry.register(id, %{"name" => "Tester"})
      assert {:ok, agent} = OpenclawMq.Registry.get_agent(id)
      assert agent["id"] == id
      assert is_binary(agent["registered_at"])
      assert is_binary(agent["last_heartbeat"])
      assert agent["name"] == "Tester"
    end

    test "returns error for unknown agent", %{prefix: p} do
      assert {:error, _} = OpenclawMq.Registry.get_agent("#{p}_ghost")
    end
  end

  describe "list_agents/0" do
    test "includes registered agents", %{prefix: p} do
      id = "#{p}_1"
      OpenclawMq.Registry.register(id)
      agents = OpenclawMq.Registry.list_agents()
      ids = Enum.map(agents, & &1["id"])
      assert id in ids
    end
  end

  describe "reap_stale/1" do
    test "removes agents whose heartbeat is older than ttl", %{prefix: p} do
      id = "#{p}_stale"
      OpenclawMq.Registry.register(id)
      # A tiny sleep so last_heartbeat_mono is in the past
      Process.sleep(5)
      # ttl of 1ms — everything registered more than 1ms ago is stale
      reaped = OpenclawMq.Registry.reap_stale(1)
      assert id in reaped
      refute OpenclawMq.Registry.online?(id)
    end

    test "keeps agents that heartbeated within ttl", %{prefix: p} do
      id = "#{p}_fresh"
      OpenclawMq.Registry.register(id)
      # Use a huge ttl so nothing is stale
      reaped = OpenclawMq.Registry.reap_stale(999_999_999)
      refute id in reaped
      assert OpenclawMq.Registry.online?(id)
    end
  end

  describe "online?/1" do
    test "returns true for registered agents", %{prefix: p} do
      id = "#{p}_1"
      OpenclawMq.Registry.register(id)
      assert OpenclawMq.Registry.online?(id)
    end

    test "returns false for unknown agents", %{prefix: p} do
      refute OpenclawMq.Registry.online?("#{p}_nobody")
    end
  end

  describe "backwards-compat register/1 (2-tuple GenServer call)" do
    test "backwards-compat handle_call clause accepts 2-element :register tuple", %{prefix: p} do
      id = "#{p}_compat"
      # Direct GenServer call with the legacy 2-tuple format
      assert :ok = GenServer.call(OpenclawMq.Registry, {:register, id})
      assert OpenclawMq.Registry.online?(id)
      OpenclawMq.Registry.unregister(id)
    end
  end

  describe "heartbeat with persisted metadata" do
    test "auto-registers with persisted metadata when available", %{prefix: p} do
      id = "#{p}_persist"
      # Register with metadata → persists to disk
      OpenclawMq.Registry.register(id, %{"name" => "Persisted Agent", "emoji" => "💾"})
      # Unregister (removes from state but leaves metadata file on disk)
      OpenclawMq.Registry.unregister(id)
      refute OpenclawMq.Registry.online?(id)

      # Heartbeat → triggers load_persisted_metadata → restores metadata
      OpenclawMq.Registry.heartbeat(id)
      assert OpenclawMq.Registry.online?(id)
      {:ok, agent} = OpenclawMq.Registry.get_agent(id)
      assert agent["name"] == "Persisted Agent"
      OpenclawMq.Registry.unregister(id)
    end
  end
end
