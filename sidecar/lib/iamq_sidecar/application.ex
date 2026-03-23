defmodule IamqSidecar.Application do
  @moduledoc "OTP Application — supervises IAMQ HTTP client and WebSocket client."
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      IamqSidecar.MqClient,
      IamqSidecar.MqWsClient
    ]

    opts = [strategy: :one_for_one, name: IamqSidecar.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
