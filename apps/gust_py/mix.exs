defmodule GustPy.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :gust_py,
      version: @version,
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      test_coverage: [tool: ExCoveralls],
      deps: deps()
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:gust, in_umbrella: true}
    ]
  end
end
