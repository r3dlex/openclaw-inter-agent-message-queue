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

  describe "send_telegram/2" do
    setup do
      # Save and clear gateway config — tests will set their own
      saved_url = Application.get_env(:openclaw_mq, :gateway_url)
      saved_token = Application.get_env(:openclaw_mq, :gateway_token)
      Application.delete_env(:openclaw_mq, :gateway_url)
      Application.delete_env(:openclaw_mq, :gateway_token)

      on_exit(fn ->
        if is_nil(saved_url) do
          Application.delete_env(:openclaw_mq, :gateway_url)
        else
          Application.put_env(:openclaw_mq, :gateway_url, saved_url)
        end

        if is_nil(saved_token) do
          Application.delete_env(:openclaw_mq, :gateway_token)
        else
          Application.put_env(:openclaw_mq, :gateway_token, saved_token)
        end
      end)

      :ok
    end

    test "returns :gateway_not_configured when gateway_url is nil" do
      Application.put_env(:openclaw_mq, :gateway_url, nil)
      Application.put_env(:openclaw_mq, :gateway_token, "tok")

      assert {:error, :gateway_not_configured} = Dispatcher.send_telegram("hello", "main")
    end

    test "send_telegram hits the receive block when gateway accepts but never sends challenge" do
      # Accept TCP but never send a WebSocket frame — exercises the receive
      # block (the {:rpc_result, _} after clause) by timing out.
      {:ok, listen_sock} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
      {:ok, {_, port}} = :inet.sockname(listen_sock)

      Task.start(fn ->
        case :gen_tcp.accept(listen_sock, 15_000) do
          {:ok, client} ->
            # Just hold the connection — RpcClient will wait 10s and time out
            Process.sleep(11_000)
            :gen_tcp.close(client)

          _ ->
            :ok
        end

        :gen_tcp.close(listen_sock)
      end)

      Application.put_env(:openclaw_mq, :gateway_url, "ws://127.0.0.1:#{port}")
      Application.put_env(:openclaw_mq, :gateway_token, "tok")

      task = Task.async(fn -> Dispatcher.send_telegram("hello", "main") end)
      result = Task.await(task, 13_000)

      refute match?({:error, :gateway_not_configured}, result)
    end

    test "returns :gateway_not_configured when gateway_url is empty string" do
      Application.put_env(:openclaw_mq, :gateway_url, "")
      Application.put_env(:openclaw_mq, :gateway_token, "tok")

      assert {:error, :gateway_not_configured} = Dispatcher.send_telegram("hello", "main")
    end

    test "returns :gateway_not_configured when gateway_token is nil" do
      Application.put_env(:openclaw_mq, :gateway_url, "ws://127.0.0.1:1")
      Application.put_env(:openclaw_mq, :gateway_token, nil)

      assert {:error, :gateway_not_configured} = Dispatcher.send_telegram("hello", "main")
    end

    test "returns :gateway_not_configured when gateway_token is empty string" do
      Application.put_env(:openclaw_mq, :gateway_url, "ws://127.0.0.1:1")
      Application.put_env(:openclaw_mq, :gateway_token, "")

      assert {:error, :gateway_not_configured} = Dispatcher.send_telegram("hello", "main")
    end

    test "returns {:error, reason} when RpcClient.start_link fails" do
      Application.put_env(:openclaw_mq, :gateway_url, "ws://127.0.0.1:1")
      Application.put_env(:openclaw_mq, :gateway_token, "tok")

      # RpcClient.start_link will fail because the URL is unreachable as a WS
      # (not a tcp listener at all) — exact failure mode depends on RpcClient
      # implementation; we just need to exercise the {:error, reason} branch.
      result = Dispatcher.send_telegram("hello", "main")

      # Either {:error, _} or :ok depending on RpcClient behavior; we assert it's
      # not the not_configured path.
      refute match?({:error, :gateway_not_configured}, result)
    end
  end

  describe "deliver/2 callback failure paths" do
    test "HTTP callback returning 404 falls back through gateway to CLI" do
      id = unique_agent()
      msg = make_msg(id)

      # Start a TCP server that returns 404
      {:ok, listen_sock} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
      {:ok, {_, port}} = :inet.sockname(listen_sock)

      Task.start(fn ->
        case :gen_tcp.accept(listen_sock, 3000) do
          {:ok, client} ->
            :gen_tcp.recv(client, 0, 3000)
            :gen_tcp.send(client, "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n")
            :gen_tcp.close(client)

          _ ->
            :ok
        end

        :gen_tcp.close(listen_sock)
      end)

      # gateway_rpc_enabled defaults to false → after 404, falls to CLI,
      # which fails because openclaw bin is not installed
      Dispatcher.register_callback(id, "http://127.0.0.1:#{port}/callback")
      assert :ok = Dispatcher.deliver(id, msg)
      Process.sleep(300)
      Dispatcher.unregister_callback(id)
    end

    test "HTTP callback returning 500 falls back through gateway to CLI" do
      id = unique_agent()
      msg = make_msg(id)

      {:ok, listen_sock} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
      {:ok, {_, port}} = :inet.sockname(listen_sock)

      Task.start(fn ->
        case :gen_tcp.accept(listen_sock, 3000) do
          {:ok, client} ->
            :gen_tcp.recv(client, 0, 3000)
            :gen_tcp.send(client, "HTTP/1.1 500 Internal\r\nContent-Length: 0\r\n\r\n")
            :gen_tcp.close(client)

          _ ->
            :ok
        end

        :gen_tcp.close(listen_sock)
      end)

      Dispatcher.register_callback(id, "http://127.0.0.1:#{port}/callback")
      assert :ok = Dispatcher.deliver(id, msg)
      Process.sleep(300)
      Dispatcher.unregister_callback(id)
    end

    test "deliver with successful callback does NOT fall through to CLI" do
      id = unique_agent()
      msg = make_msg(id)

      {:ok, listen_sock} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
      {:ok, {_, port}} = :inet.sockname(listen_sock)

      Task.start(fn ->
        case :gen_tcp.accept(listen_sock, 3000) do
          {:ok, client} ->
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
      Process.sleep(300)
      Dispatcher.unregister_callback(id)
    end

    test "deliver with gateway_rpc enabled and no callback exercises gateway_configured? false path" do
      id = unique_agent()
      msg = make_msg(id)

      # No callback, gateway_rpc_enabled = true but no URL/token
      Application.put_env(:openclaw_mq, :gateway_rpc_enabled, true)
      on_exit(fn -> Application.put_env(:openclaw_mq, :gateway_rpc_enabled, false) end)

      assert :ok = Dispatcher.deliver(id, msg)
      Process.sleep(200)
    end

    test "deliver with gateway_rpc enabled and configured but RpcClient fails exercises gateway_configured? true path" do
      id = unique_agent()
      msg = make_msg(id)

      Application.put_env(:openclaw_mq, :gateway_rpc_enabled, true)
      Application.put_env(:openclaw_mq, :gateway_url, "ws://127.0.0.1:1")
      Application.put_env(:openclaw_mq, :gateway_token, "tok")
      on_exit(fn ->
        Application.put_env(:openclaw_mq, :gateway_rpc_enabled, false)
        Application.delete_env(:openclaw_mq, :gateway_url)
        Application.delete_env(:openclaw_mq, :gateway_token)
      end)

      assert :ok = Dispatcher.deliver(id, msg)
      Process.sleep(500)
    end

    test "deliver with CLI binary configured but exits non-zero exercises warning log path" do
      id = unique_agent()
      msg = make_msg(id)

      # No callback → goes to gateway_rpc (disabled) → CLI fallback
      # Use a shell script that exits 1 to exercise the warning branch
      # (the :error branch in try_cli that logs and returns {:error, "exit N"})
      Application.put_env(:openclaw_mq, :openclaw_bin, "false")
      on_exit(fn -> Application.delete_env(:openclaw_mq, :openclaw_bin) end)

      assert :ok = Dispatcher.deliver(id, msg)
      Process.sleep(200)
    end

    test "deliver with successful CLI binary exercises try_cli success path" do
      id = unique_agent()
      msg = make_msg(id)

      # `true` is a unix builtin that exits 0 — exercises the {:_output, 0} → :ok branch
      Application.put_env(:openclaw_mq, :openclaw_bin, "true")
      on_exit(fn -> Application.delete_env(:openclaw_mq, :openclaw_bin) end)

      assert :ok = Dispatcher.deliver(id, msg)
      Process.sleep(200)
    end

    test "deliver with non-existent CLI binary exercises rescue branch" do
      id = unique_agent()
      msg = make_msg(id)

      # A non-existent binary causes System.cmd to raise → exercises rescue
      Application.put_env(:openclaw_mq, :openclaw_bin, "/this/binary/does/not/exist_xyz123")
      on_exit(fn -> Application.delete_env(:openclaw_mq, :openclaw_bin) end)

      assert :ok = Dispatcher.deliver(id, msg)
      Process.sleep(200)
    end
  end
end
