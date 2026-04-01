defmodule OpenclawMq.Gateway.DispatcherTest do
  use ExUnit.Case, async: false

  alias OpenclawMq.Gateway.Dispatcher

  defp unique_agent, do: "disp_test_#{:erlang.unique_integer([:positive])}"

  defp make_msg(to) do
    {:ok, msg} =
      OpenclawMq.Message.new(%{
        "from" => "dispatcher_test",
        "to" => to,
        "type" => "info",
        "subject" => "dispatcher test",
        "body" => "test body"
      })

    msg
  end

  describe "register_callback/2 and get_callback/1" do
    test "registers a callback URL" do
      id = unique_agent()
      assert :ok = Dispatcher.register_callback(id, "http://localhost:9100/cb")
      assert {:ok, "http://localhost:9100/cb"} = Dispatcher.get_callback(id)
      Dispatcher.unregister_callback(id)
    end

    test "returns :none when no callback is registered" do
      id = unique_agent()
      assert :none = Dispatcher.get_callback(id)
    end
  end

  describe "unregister_callback/1" do
    test "removes a registered callback" do
      id = unique_agent()
      Dispatcher.register_callback(id, "http://localhost:9100/cb")
      assert :ok = Dispatcher.unregister_callback(id)
      assert :none = Dispatcher.get_callback(id)
    end

    test "unregistering a non-existent callback is a no-op" do
      assert :ok = Dispatcher.unregister_callback("ghost_#{unique_agent()}")
    end
  end

  describe "deliver/2" do
    test "deliver with no callback does not raise (passive fallback path)" do
      id = unique_agent()
      msg = make_msg(id)
      # No callback registered — should log and fall through silently
      assert :ok = Dispatcher.deliver(id, msg)
      # Allow the async cast to complete
      Process.sleep(150)
    end

    test "deliver with a registered callback that is unreachable falls back gracefully" do
      id = unique_agent()
      # Register a callback to a port where nothing is listening
      Dispatcher.register_callback(id, "http://127.0.0.1:19999/callback")
      msg = make_msg(id)
      # Should not raise even if HTTP call fails
      assert :ok = Dispatcher.deliver(id, msg)
      Process.sleep(300)
      Dispatcher.unregister_callback(id)
    end

    test "deliver with a successful HTTP callback (mock server returns 200)" do
      id = unique_agent()
      msg = make_msg(id)

      # Start a minimal TCP server that responds with HTTP 200
      {:ok, listen_sock} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
      {:ok, {_, port}} = :inet.sockname(listen_sock)

      Task.start(fn ->
        case :gen_tcp.accept(listen_sock, 3000) do
          {:ok, client} ->
            # Drain the HTTP request
            :gen_tcp.recv(client, 0, 3000)
            :gen_tcp.send(client, "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok")
            :gen_tcp.close(client)

          _ ->
            :ok
        end

        :gen_tcp.close(listen_sock)
      end)

      Dispatcher.register_callback(id, "http://127.0.0.1:#{port}/callback")
      assert :ok = Dispatcher.deliver(id, msg)
      # Allow the async cast + HTTP call to complete
      Process.sleep(300)
      Dispatcher.unregister_callback(id)
    end

    test "deliver with gateway_rpc_enabled falls back to CLI when gateway is unavailable" do
      id = unique_agent()
      msg = make_msg(id)
      Application.put_env(:openclaw_mq, :gateway_rpc_enabled, true)
      Application.put_env(:openclaw_mq, :gateway_url, "ws://127.0.0.1:19998")

      assert :ok = Dispatcher.deliver(id, msg)
      Process.sleep(300)

      Application.put_env(:openclaw_mq, :gateway_rpc_enabled, false)
    end
  end

  describe "Message struct compatibility" do
    test "valid_status?/1 accepts all valid statuses" do
      for s <- ~w(unread read acted archived) do
        assert OpenclawMq.Message.valid_status?(s)
      end
    end

    test "valid_status?/1 rejects invalid statuses" do
      refute OpenclawMq.Message.valid_status?("flying")
      refute OpenclawMq.Message.valid_status?("")
    end

    test "from_map/1 round-trips through to_map/1" do
      {:ok, original} =
        OpenclawMq.Message.new(%{
          "from" => "a",
          "to" => "b",
          "type" => "request",
          "subject" => "test",
          "body" => "hello",
          "priority" => "HIGH"
        })

      map = OpenclawMq.Message.to_map(original)
      restored = OpenclawMq.Message.from_map(map)

      assert restored.id == original.id
      assert restored.from == original.from
      assert restored.to == original.to
      assert restored.priority == original.priority
      assert restored.subject == original.subject
      assert restored.status == original.status
    end

    test "from_map/1 with optional fields" do
      map = %{
        "id" => "test-id",
        "from" => "a",
        "to" => "b",
        "type" => "info",
        "subject" => "s",
        "body" => "b",
        "replyTo" => "prev-id",
        "expiresAt" => "2099-01-01T00:00:00Z",
        "status" => "read",
        "createdAt" => "2026-01-01T00:00:00Z"
      }

      msg = OpenclawMq.Message.from_map(map)
      assert msg.reply_to == "prev-id"
      assert msg.expires_at == "2099-01-01T00:00:00Z"
      assert msg.status == "read"
    end
  end
end
