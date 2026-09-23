defmodule GustShell.MixProject do
  use Mix.Project

  @version "0.1.0"
  @gust_version "0.1.40"

  def project do
    [
      app: :gust_shell,
      version: @version,
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.cobertura": :test
      ],
      deps: deps(),
      description: "YAML shell DAG support for Gust",
      package: [
        licenses: ["MIT"],
        links: %{"GitHub" => "https://github.com/marciok/gust"},
        files: [
          "lib",
          "guides",
          "mix.exs",
          "README.md"
        ]
      ],
      docs: docs()
    ]
  end

  def application do
    [extra_applications: [:logger, :runtime_tools, :erlexec]]
  end

  defp deps do
    [
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:erlexec, "~> 2.5"},
      {:glazer, "~> 1.0"},
      gust_dep()
    ]
  end

  defp gust_dep() do
    if System.get_env("PUBLISH_DEP") == "true" do
      {:gust, @gust_version}
    else
      {:gust, in_umbrella: true}
    end
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: "https://github.com/marciok/gust",
      extras: extras(),
      groups_for_extras: groups_for_extras()
    ]
  end

  defp extras, do: ["README.md"] ++ Path.wildcard("guides/*.md")
  defp groups_for_extras, do: [Guides: Path.wildcard("guides/*.md")]
end
