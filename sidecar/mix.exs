defmodule IamqSidecar.MixProject do
  use Mix.Project

  def project do
    [
      app: :iamq_sidecar,
      version: "0.1.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {IamqSidecar.Application, []}
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:req, "~> 0.5"},
      {:websockex, "~> 0.5"}
    ]
  end
end
