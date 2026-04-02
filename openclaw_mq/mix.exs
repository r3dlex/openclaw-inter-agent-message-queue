defmodule OpenclawMq.MixProject do
  use Mix.Project

  def project do
    [
      app: :openclaw_mq,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "OpenclawMq",
      source_url: "https://github.com/r3dlex/openclaw-inter-agent-message-queue",
      docs: [
        main: "readme",
        extras:
          ["README.md"] ++
            if(File.exists?("spec"), do: Path.wildcard("spec/*.md"), else: []),
        output: "doc/",
        formatters: ["html"]
      ],
      test_coverage: [
        summary: [threshold: 90],
        # WebSocket upgrade handler and gateway WS RPC client require live connections
        ignore_modules: [
          OpenclawMq.Api.WsHandler,
          OpenclawMq.Api.WsRouter,
          OpenclawMq.Gateway.RpcClient,
          OpenclawMq.Application
        ]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :inets, :ssl],
      mod: {OpenclawMq.Application, []}
    ]
  end

  defp deps do
    [
      {:plug_cowboy, "~> 2.7"},
      {:jason, "~> 1.4"},
      {:phoenix_pubsub, "~> 2.1"},
      {:websockex, "~> 0.4"},
      {:uuid, "~> 1.1"},
      {:crontab, "~> 1.1"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end
end
