defmodule GustWeb.MixProject do
  use Mix.Project

  @version "0.1.25"

  def project do
    [
      app: :gust_web,
      version: @version,
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      test_coverage: [tool: ExCoveralls],
      description: "The web interface for Gust",
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

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {GustWeb.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:phoenix, "~> 1.8.0"},
      {:phoenix_ecto, "~> 4.5"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.1.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.26"},
      gust_dep(),
      {:jason, "~> 1.2"},
      {:bandit, "~> 1.5"}
    ]
    |> maybe_add_heroicons()
  end

  defp gust_dep() do
    if publish_dep?() do
      {:gust, "#{@version}"}
    else
      {:gust, in_umbrella: true}
    end
  end

  defp maybe_add_heroicons(deps) do
    if publish_dep?() do
      deps
    else
      deps ++
        [
          {:heroicons,
           github: "tailwindlabs/heroicons",
           tag: "v2.2.0",
           sparse: "optimized",
           app: false,
           compile: false,
           depth: 1}
        ]
    end
  end

  defp publish_dep?(), do: System.get_env("PUBLISH_DEP") == "true"

  # Aliases are shortcuts or tasks specific to the current project.
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "assets.setup", "assets.build"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind gust_web", "esbuild gust_web"],
      "assets.deploy": [
        "tailwind gust_web --minify",
        "esbuild gust_web --minify",
        "phx.digest"
      ]
    ]
  end
end
