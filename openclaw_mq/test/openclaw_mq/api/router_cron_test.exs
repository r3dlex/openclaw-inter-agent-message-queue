defmodule OpenclawMq.Api.RouterCronTest do
  use ExUnit.Case, async: false
  use Plug.Test

  alias OpenclawMq.Api.Router
  alias OpenclawMq.Cron.Store

  @opts Router.init([])

  setup do
    Store.init()
    :ets.delete_all_objects(:cron_entries)

    # Ensure the Scheduler is running (it may not be in test env)
    if is_nil(GenServer.whereis(OpenclawMq.Cron.Scheduler)) do
      {:ok, _} = OpenclawMq.Cron.Scheduler.start_link([])
    end

    :ok
  end

  defp call_json(method, path, body) do
    conn(method, path, Jason.encode!(body))
    |> put_req_header("content-type", "application/json")
    |> Router.call(@opts)
  end

  defp call(method, path) do
    conn(method, path)
    |> put_req_header("content-type", "application/json")
    |> Router.call(@opts)
  end

  defp json_body(conn), do: Jason.decode!(conn.resp_body)

  defp valid_cron_params(overrides \\ %{}) do
    Map.merge(
      %{
        "agent_id" => "mail_agent",
        "name" => "tidy_inbox_#{:erlang.unique_integer([:positive])}",
        "expression" => "30 6 * * *",
        "enabled" => true
      },
      overrides
    )
  end

  describe "POST /crons" do
    test "valid payload returns 201 with entry JSON" do
      conn = call_json(:post, "/crons", valid_cron_params())
      assert conn.status == 201
      body = json_body(conn)
      assert is_binary(body["id"])
      assert body["agent_id"] == "mail_agent"
      assert body["expression"] == "30 6 * * *"
      assert body["enabled"] == true
    end

    test "missing agent_id returns 422" do
      conn = call_json(:post, "/crons", %{"name" => "x", "expression" => "0 * * * *"})
      assert conn.status == 422
      assert is_binary(json_body(conn)["error"])
    end

    test "invalid cron expression returns 422" do
      params = valid_cron_params(%{"expression" => "not a cron"})
      conn = call_json(:post, "/crons", params)
      assert conn.status == 422
      assert is_binary(json_body(conn)["error"])
    end

    test "missing name returns 422" do
      conn = call_json(:post, "/crons", %{"agent_id" => "a", "expression" => "0 * * * *"})
      assert conn.status == 422
      assert is_binary(json_body(conn)["error"])
    end
  end

  describe "GET /crons" do
    test "returns 200 with list (possibly empty)" do
      conn = call(:get, "/crons")
      assert conn.status == 200
      body = json_body(conn)
      assert is_list(body["crons"])
    end

    test "returns all registered crons" do
      call_json(:post, "/crons", valid_cron_params(%{"agent_id" => "agent_a"}))
      call_json(:post, "/crons", valid_cron_params(%{"agent_id" => "agent_b"}))
      conn = call(:get, "/crons")
      assert conn.status == 200
      assert length(json_body(conn)["crons"]) >= 2
    end

    test "GET /crons?agent_id=x returns filtered list" do
      unique_agent = "filter_agent_#{:erlang.unique_integer([:positive])}"
      call_json(:post, "/crons", valid_cron_params(%{"agent_id" => unique_agent}))
      call_json(:post, "/crons", valid_cron_params(%{"agent_id" => "other_agent"}))

      conn = call(:get, "/crons?agent_id=#{unique_agent}")
      assert conn.status == 200
      body = json_body(conn)
      assert Enum.all?(body["crons"], &(&1["agent_id"] == unique_agent))
      assert length(body["crons"]) >= 1
    end
  end

  describe "GET /crons/:id" do
    test "existing id returns 200 with entry JSON" do
      post_conn = call_json(:post, "/crons", valid_cron_params())
      assert post_conn.status == 201
      id = json_body(post_conn)["id"]

      conn = call(:get, "/crons/#{id}")
      assert conn.status == 200
      assert json_body(conn)["id"] == id
    end

    test "unknown id returns 404" do
      conn = call(:get, "/crons/no-such-cron-id")
      assert conn.status == 404
      assert is_binary(json_body(conn)["error"])
    end
  end

  describe "PATCH /crons/:id" do
    test "disabling entry returns 200 with updated entry" do
      post_conn = call_json(:post, "/crons", valid_cron_params())
      id = json_body(post_conn)["id"]

      conn = call_json(:patch, "/crons/#{id}", %{"enabled" => false})
      assert conn.status == 200
      body = json_body(conn)
      assert body["enabled"] == false
    end

    test "enabling entry returns 200 with enabled: true" do
      post_conn = call_json(:post, "/crons", valid_cron_params(%{"enabled" => false}))
      id = json_body(post_conn)["id"]

      conn = call_json(:patch, "/crons/#{id}", %{"enabled" => true})
      assert conn.status == 200
      assert json_body(conn)["enabled"] == true
    end

    test "unknown id returns 404" do
      conn = call_json(:patch, "/crons/no-such-id", %{"enabled" => false})
      assert conn.status == 404
    end
  end

  describe "DELETE /crons/:id" do
    test "existing id returns 200" do
      post_conn = call_json(:post, "/crons", valid_cron_params())
      id = json_body(post_conn)["id"]

      conn = call(:delete, "/crons/#{id}")
      assert conn.status == 200
      assert json_body(conn)["status"] == "deleted"
    end

    test "after delete, GET /crons/:id returns 404" do
      post_conn = call_json(:post, "/crons", valid_cron_params())
      id = json_body(post_conn)["id"]

      call(:delete, "/crons/#{id}")
      conn = call(:get, "/crons/#{id}")
      assert conn.status == 404
    end

    test "unknown id returns 404" do
      conn = call(:delete, "/crons/no-such-id")
      assert conn.status == 404
    end
  end
end
