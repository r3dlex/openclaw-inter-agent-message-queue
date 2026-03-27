defmodule IamqSidecarTest do
  @moduledoc "Smoke tests — verify modules compile and core APIs exist."
  use ExUnit.Case, async: false

  describe "module existence" do
    test "IamqSidecar.Application is defined" do
      assert Code.ensure_loaded?(IamqSidecar.Application)
    end

    test "IamqSidecar.MqClient is defined" do
      assert Code.ensure_loaded?(IamqSidecar.MqClient)
    end

    test "IamqSidecar.MqWsClient is defined" do
      assert Code.ensure_loaded?(IamqSidecar.MqWsClient)
    end
  end

  describe "MqClient public API" do
    test "exports expected functions" do
      Code.ensure_loaded!(IamqSidecar.MqClient)

      assert function_exported?(IamqSidecar.MqClient, :start_link, 1)
      assert function_exported?(IamqSidecar.MqClient, :send_message, 4)
      assert function_exported?(IamqSidecar.MqClient, :broadcast, 3)
      assert function_exported?(IamqSidecar.MqClient, :inbox, 1)
      assert function_exported?(IamqSidecar.MqClient, :agents, 0)
      assert function_exported?(IamqSidecar.MqClient, :status, 0)
    end
  end

  describe "MqWsClient" do
    test "exports start_link/1" do
      Code.ensure_loaded!(IamqSidecar.MqWsClient)
      assert function_exported?(IamqSidecar.MqWsClient, :start_link, 1)
    end
  end
end
