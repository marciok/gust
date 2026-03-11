defmodule GustPy.MixProject do
  use Mix.Project

  @version "0.1.1"
  @gust_version "0.1.28"

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
      deps: deps(),
      description: "Python DAG support for Gust",
      package: [
        licenses: ["Apache-2.0"],
        links: %{"GitHub" => "https://github.com/marciok/gust"},
        files: [
          "lib",
          "mix.exs",
          "README.md"
        ]
      ]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      gust_dep()
    ]
  end

  defp gust_dep() do
    if publish_dep?() do
      {:gust, @gust_version}
    else
      {:gust, in_umbrella: true}
    end
  end

  defp publish_dep?(), do: System.get_env("PUBLISH_DEP") == "true"
end
