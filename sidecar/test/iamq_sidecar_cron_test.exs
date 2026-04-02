defmodule IamqSidecar.CronTest do
  @moduledoc """
  Tests for cron management functions in IamqSidecar.MqClient.

  HTTP calls are intercepted by injecting a custom Req `:adapter` via
  `Application.put_env(:iamq_sidecar, :req_options, ...)` — no live
  server or Plug dependency needed.
  """
  use ExUnit.Case, async: false

  alias IamqSidecar.MqClient

  # Shared cron fixture
  @cron_entry %{
    "id" => "cron-abc-123",
    "agent_id" => "test_agent",
    "name" => "morning-report",
    "expression" => "0 8 * * *",
    "enabled" => true
  }

  # Helper: build a Req adapter returning a JSON response at the given status.
  defp json_adapter(status, body) do
    fn req ->
      {req, Req.Response.json(%Req.Response{status: status}, body)}
    end
  end

  # Store the adapter in Application env so the implementation picks it up.
  defp set_adapter(adapter) do
    Application.put_env(:iamq_sidecar, :req_options, adapter: adapter)
  end

  setup do
    on_exit(fn -> Application.delete_env(:iamq_sidecar, :req_options) end)
    :ok
  end

  # ---------------------------------------------------------------------------
  # API surface
  # ---------------------------------------------------------------------------

  describe "MqClient cron API surface" do
    test "exports register_cron/3" do
      assert function_exported?(MqClient, :register_cron, 3)
    end

    test "exports list_crons/1" do
      assert function_exported?(MqClient, :list_crons, 1)
    end

    test "exports get_cron/1" do
      assert function_exported?(MqClient, :get_cron, 1)
    end

    test "exports update_cron/2" do
      assert function_exported?(MqClient, :update_cron, 2)
    end

    test "exports delete_cron/1" do
      assert function_exported?(MqClient, :delete_cron, 1)
    end
  end

  # ---------------------------------------------------------------------------
  # register_cron/3
  # ---------------------------------------------------------------------------

  describe "register_cron/3" do
    test "returns {:ok, cron_entry} on HTTP 201" do
      set_adapter(fn req ->
        assert req.method == :post
        assert URI.to_string(req.url) =~ "/crons"
        {req, Req.Response.json(%Req.Response{status: 201}, @cron_entry)}
      end)

      assert {:ok, entry} = MqClient.register_cron("morning-report", "0 8 * * *")
      assert entry["id"] == "cron-abc-123"
      assert entry["name"] == "morning-report"
    end

    test "returns {:ok, cron_entry} on HTTP 200" do
      set_adapter(json_adapter(200, @cron_entry))

      assert {:ok, entry} = MqClient.register_cron("morning-report", "0 8 * * *")
      assert entry["expression"] == "0 8 * * *"
    end

    test "passes enabled: false option in body" do
      set_adapter(fn req ->
        body = Jason.decode!(req.body)
        assert body["enabled"] == false

        {req,
         Req.Response.json(%Req.Response{status: 201}, Map.put(@cron_entry, "enabled", false))}
      end)

      assert {:ok, entry} = MqClient.register_cron("daily", "0 0 * * *", enabled: false)
      assert entry["enabled"] == false
    end

    test "returns {:error, reason} on HTTP 422" do
      set_adapter(json_adapter(422, %{"error" => "invalid expression"}))

      assert {:error, reason} = MqClient.register_cron("bad", "not-a-cron")
      assert reason =~ "422"
    end

    test "returns {:error, reason} on network error" do
      set_adapter(fn req ->
        {req, %Req.TransportError{reason: :econnrefused}}
      end)

      assert {:error, _reason} = MqClient.register_cron("down", "* * * * *")
    end
  end

  # ---------------------------------------------------------------------------
  # list_crons/1
  # ---------------------------------------------------------------------------

  describe "list_crons/1" do
    test "returns {:ok, list} on HTTP 200" do
      set_adapter(fn req ->
        assert req.method == :get
        assert URI.to_string(req.url) =~ "/crons"
        {req, Req.Response.json(%Req.Response{status: 200}, [@cron_entry])}
      end)

      assert {:ok, [entry | _]} = MqClient.list_crons()
      assert entry["id"] == "cron-abc-123"
    end

    test "appends agent_id query param" do
      set_adapter(fn req ->
        assert URI.to_string(req.url) =~ "agent_id="
        {req, Req.Response.json(%Req.Response{status: 200}, [])}
      end)

      assert {:ok, []} = MqClient.list_crons()
    end

    test "accepts :agent_id override option" do
      set_adapter(fn req ->
        assert URI.to_string(req.url) =~ "agent_id=other_agent"
        {req, Req.Response.json(%Req.Response{status: 200}, [])}
      end)

      assert {:ok, []} = MqClient.list_crons(agent_id: "other_agent")
    end

    test "returns {:error, reason} on HTTP 500" do
      set_adapter(json_adapter(500, %{"error" => "server error"}))

      assert {:error, reason} = MqClient.list_crons()
      assert reason =~ "500"
    end
  end

  # ---------------------------------------------------------------------------
  # get_cron/1
  # ---------------------------------------------------------------------------

  describe "get_cron/1" do
    test "returns {:ok, entry} on HTTP 200" do
      set_adapter(fn req ->
        assert req.method == :get
        assert URI.to_string(req.url) =~ "/crons/cron-abc-123"
        {req, Req.Response.json(%Req.Response{status: 200}, @cron_entry)}
      end)

      assert {:ok, entry} = MqClient.get_cron("cron-abc-123")
      assert entry["expression"] == "0 8 * * *"
    end

    test "returns {:error, reason} on HTTP 404" do
      set_adapter(json_adapter(404, %{"error" => "not found"}))

      assert {:error, reason} = MqClient.get_cron("missing-id")
      assert reason =~ "404"
    end
  end

  # ---------------------------------------------------------------------------
  # update_cron/2
  # ---------------------------------------------------------------------------

  describe "update_cron/2" do
    test "returns {:ok, updated_entry} on HTTP 200" do
      updated = Map.put(@cron_entry, "enabled", false)

      set_adapter(fn req ->
        assert req.method == :patch
        assert URI.to_string(req.url) =~ "/crons/cron-abc-123"
        {req, Req.Response.json(%Req.Response{status: 200}, updated)}
      end)

      assert {:ok, entry} = MqClient.update_cron("cron-abc-123", %{enabled: false})
      assert entry["enabled"] == false
    end

    test "returns {:error, reason} on HTTP 404" do
      set_adapter(json_adapter(404, %{"error" => "not found"}))

      assert {:error, reason} = MqClient.update_cron("ghost-id", %{enabled: true})
      assert reason =~ "404"
    end
  end

  # ---------------------------------------------------------------------------
  # delete_cron/1
  # ---------------------------------------------------------------------------

  describe "delete_cron/1" do
    test "returns :ok on HTTP 200" do
      set_adapter(fn req ->
        assert req.method == :delete
        assert URI.to_string(req.url) =~ "/crons/cron-abc-123"
        {req, %Req.Response{status: 200, body: ""}}
      end)

      assert :ok = MqClient.delete_cron("cron-abc-123")
    end

    test "returns :ok on HTTP 204" do
      set_adapter(fn req ->
        {req, %Req.Response{status: 204, body: ""}}
      end)

      assert :ok = MqClient.delete_cron("cron-abc-123")
    end

    test "returns {:error, reason} on HTTP 404" do
      set_adapter(json_adapter(404, %{"error" => "not found"}))

      assert {:error, reason} = MqClient.delete_cron("ghost-id")
      assert reason =~ "404"
    end
  end
end
