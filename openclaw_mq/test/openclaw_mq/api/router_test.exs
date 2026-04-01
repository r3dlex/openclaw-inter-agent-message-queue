defmodule OpenclawMq.Api.RouterTest do
  use ExUnit.Case, async: false
  use Plug.Test

  alias OpenclawMq.Api.Router

  @opts Router.init([])

  defp call(method, path, body \\ nil) do
    conn =
      conn(method, path, body)
      |> put_req_header("content-type", "application/json")

    Router.call(conn, @opts)
  end

  defp call_json(method, path, body) do
    conn(method, path, Jason.encode!(body))
    |> put_req_header("content-type", "application/json")
    |> Router.call(@opts)
  end

  defp json_body(conn) do
    Jason.decode!(conn.resp_body)
  end

  defp unique_agent, do: "router_test_#{:erlang.unique_integer([:positive])}"

  describe "POST /register" do
    test "registers an agent and returns 200" do
      id = unique_agent()
      conn = call_json(:post, "/register", %{"agent_id" => id})
      assert conn.status == 200
      body = json_body(conn)
      assert body["status"] == "registered"
      assert body["agent_id"] == id
      OpenclawMq.Registry.unregister(id)
    end

    test "registers with metadata" do
      id = unique_agent()

      conn =
        call_json(:post, "/register", %{"agent_id" => id, "name" => "My Agent", "emoji" => "🤖"})

      assert conn.status == 200
      {:ok, agent} = OpenclawMq.Registry.get_agent(id)
      assert agent["name"] == "My Agent"
      OpenclawMq.Registry.unregister(id)
    end
  end

  describe "POST /heartbeat" do
    test "returns 200 ok" do
      id = unique_agent()
      OpenclawMq.Registry.register(id)
      conn = call_json(:post, "/heartbeat", %{"agent_id" => id})
      assert conn.status == 200
      assert json_body(conn)["status"] == "ok"
      OpenclawMq.Registry.unregister(id)
    end
  end

  describe "POST /send" do
    test "creates message and returns 201" do
      from_id = unique_agent()
      to_id = unique_agent()
      OpenclawMq.Registry.register(from_id)
      OpenclawMq.Registry.register(to_id)

      conn =
        call_json(:post, "/send", %{
          "from" => from_id,
          "to" => to_id,
          "type" => "info",
          "subject" => "hello",
          "body" => "test"
        })

      assert conn.status == 201
      body = json_body(conn)
      assert body["from"] == from_id
      assert body["to"] == to_id
      assert body["subject"] == "hello"
      assert is_binary(body["id"])

      OpenclawMq.Registry.unregister(from_id)
      OpenclawMq.Registry.unregister(to_id)
    end

    test "returns 400 for invalid priority" do
      conn =
        call_json(:post, "/send", %{
          "from" => "a",
          "to" => "b",
          "type" => "info",
          "subject" => "x",
          "body" => "y",
          "priority" => "NOPE"
        })

      assert conn.status == 400
      assert json_body(conn)["error"] =~ "invalid priority"
    end

    test "returns 400 for invalid type" do
      conn =
        call_json(:post, "/send", %{
          "from" => "a",
          "to" => "b",
          "type" => "banana",
          "subject" => "x",
          "body" => "y"
        })

      assert conn.status == 400
      assert json_body(conn)["error"] =~ "invalid type"
    end

    test "broadcast send triggers delivery to other agents" do
      from_id = unique_agent()
      OpenclawMq.Registry.register(from_id)

      conn =
        call_json(:post, "/send", %{
          "from" => from_id,
          "to" => "broadcast",
          "type" => "info",
          "subject" => "broadcast test",
          "body" => "hello all"
        })

      assert conn.status == 201
      OpenclawMq.Registry.unregister(from_id)
    end
  end

  describe "GET /inbox/:agent_id" do
    test "returns messages for an agent" do
      to_id = unique_agent()

      {:ok, msg} =
        OpenclawMq.Message.new(%{
          "from" => "sender",
          "to" => to_id,
          "type" => "info",
          "subject" => "inbox test",
          "body" => "body"
        })

      OpenclawMq.Store.put(msg)

      conn = call(:get, "/inbox/#{to_id}")
      assert conn.status == 200
      body = json_body(conn)
      assert is_list(body["messages"])
      assert Enum.any?(body["messages"], &(&1["id"] == msg.id))
    end

    test "filters by status query param" do
      to_id = unique_agent()
      conn = call(:get, "/inbox/#{to_id}?status=unread")
      assert conn.status == 200
      assert is_list(json_body(conn)["messages"])
    end
  end

  describe "PATCH /messages/:id" do
    test "updates message status to read" do
      {:ok, msg} =
        OpenclawMq.Message.new(%{
          "from" => "a",
          "to" => unique_agent(),
          "type" => "info",
          "subject" => "patch test",
          "body" => "body"
        })

      OpenclawMq.Store.put(msg)

      conn = call_json(:patch, "/messages/#{msg.id}", %{"status" => "read"})
      assert conn.status == 200
      assert json_body(conn)["status"] == "updated"
    end

    test "returns 404 for unknown message ID" do
      conn = call_json(:patch, "/messages/no-such-id", %{"status" => "read"})
      assert conn.status == 404
    end
  end

  describe "GET /status" do
    test "returns queue summary with agents_online and queues" do
      conn = call(:get, "/status")
      assert conn.status == 200
      body = json_body(conn)
      assert is_binary(body["checkedAt"])
      assert is_map(body["queues"])
      assert is_list(body["agents_online"])
    end
  end

  describe "POST /callback and DELETE /callback" do
    test "registers and removes a callback URL" do
      id = unique_agent()

      conn =
        call_json(:post, "/callback", %{"agent_id" => id, "url" => "http://localhost:9999/cb"})

      assert conn.status == 200
      assert json_body(conn)["status"] == "callback_registered"

      conn2 = call_json(:delete, "/callback", %{"agent_id" => id})
      assert conn2.status == 200
      assert json_body(conn2)["status"] == "callback_removed"
    end
  end

  describe "GET /agents" do
    test "returns list of agents" do
      id = unique_agent()
      OpenclawMq.Registry.register(id)
      conn = call(:get, "/agents")
      assert conn.status == 200
      body = json_body(conn)
      assert is_list(body["agents"])
      assert Enum.any?(body["agents"], &(&1["id"] == id))
      OpenclawMq.Registry.unregister(id)
    end
  end

  describe "GET /agents/:agent_id" do
    test "returns agent profile" do
      id = unique_agent()
      OpenclawMq.Registry.register(id, %{"name" => "Router Test Agent"})
      conn = call(:get, "/agents/#{id}")
      assert conn.status == 200
      body = json_body(conn)
      assert body["id"] == id
      assert body["name"] == "Router Test Agent"
      OpenclawMq.Registry.unregister(id)
    end

    test "returns 404 for unknown agent" do
      conn = call(:get, "/agents/no_such_agent_xyz")
      assert conn.status == 404
    end
  end

  describe "PUT /agents/:agent_id" do
    test "updates agent metadata" do
      id = unique_agent()
      OpenclawMq.Registry.register(id, %{"name" => "Old"})
      conn = call_json(:put, "/agents/#{id}", %{"name" => "Updated"})
      assert conn.status == 200
      assert json_body(conn)["name"] == "Updated"
      OpenclawMq.Registry.unregister(id)
    end

    test "returns 404 for unregistered agent" do
      conn = call_json(:put, "/agents/ghost_agent_xyz", %{"name" => "x"})
      assert conn.status == 404
    end
  end

  describe "catch-all" do
    test "returns 404 for unknown routes" do
      conn = call(:get, "/no/such/route")
      assert conn.status == 404
      assert json_body(conn)["error"] == "not found"
    end
  end
end
