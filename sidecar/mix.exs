defmodule IamqSidecar.MixProject do
  use Mix.Project

  def project do
    [
      app: :iamq_sidecar,
      version: "0.1.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      test_coverage: [summary: [threshold: 0]],
      name: "IamqSidecar",
      source_url: "https://github.com/r3dlex/openclaw-inter-agent-message-queue",
      docs: [
        main: "IamqSidecar.MqClient",
        extras:
          if(File.exists?("README.md"), do: ["README.md"], else: []) ++
            if(File.exists?("spec"), do: Path.wildcard("spec/*.md"), else: []),
        output: "doc/",
        formatters: ["html"]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {IamqSidecar.Application, []}
    ]
  end

  defp aliases do
    [
      test: ["test --no-start"]
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:req, "~> 0.5"},
      {:websockex, "~> 0.5"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end
end
