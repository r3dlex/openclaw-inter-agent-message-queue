defmodule OpenclawMq.ReaperTest do
  use ExUnit.Case, async: false

  test "reaper process is alive" do
    assert pid = Process.whereis(OpenclawMq.Reaper)
    assert is_pid(pid)
    assert Process.alive?(pid)
  end

  test "manual :reap message triggers cleanup without crashing" do
    pid = Process.whereis(OpenclawMq.Reaper)
    # Register a stale agent
    id = "reaper_test_#{:erlang.unique_integer([:positive])}"
    OpenclawMq.Registry.register(id)
    Process.sleep(5)

    # Override TTL to 1ms so the agent we just registered is stale
    Application.put_env(:openclaw_mq, :agent_ttl_ms, 1)
    send(pid, :reap)
    # Allow handle_info to complete
    Process.sleep(50)
    Application.put_env(:openclaw_mq, :agent_ttl_ms, 300_000)

    # Agent should have been reaped
    refute OpenclawMq.Registry.online?(id)
  end
end
