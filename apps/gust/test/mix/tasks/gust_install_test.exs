defmodule Mix.Tasks.Gust.InstallTest do
  use ExUnit.Case

  import Igniter.Test

  defp phoenix_project do
    test_project(
      app_name: :my_app,
      files: %{
        "lib/my_app_web/router.ex" => """
        defmodule MyAppWeb.Router do
          use Phoenix.Router

          pipeline :browser do
            plug :accepts, ["html"]
          end

          scope "/", MyAppWeb do
            pipe_through :browser
          end
        end
        """,
        "config/config.exs" => """
        import Config
        """,
        "config/dev.exs" => """
        import Config
        """,
        "config/test.exs" => """
        import Config
        """,
        "config/runtime.exs" => """
        import Config
        """
      }
    )
  end

  test "installs into a phoenix project" do
    phoenix_project()
    |> Igniter.compose_task("gust.install")
    |> assert_has_patch("config/config.exs", """
    + | config :gust_web, dashboard_path: "/gust"
    """)
    |> assert_has_patch("config/config.exs", """
    + |  app_name: :my_app,
    """)
    |> assert_creates("dags/.keep")
    |> assert_has_notice(&String.contains?(&1, "Gust installed"))
  end

  test "adds import and scope to router" do
    phoenix_project()
    |> Igniter.compose_task("gust.install")
    |> assert_has_patch("lib/my_app_web/router.ex", """
    + | import GustWeb.DashboardRouter
    """)
    |> assert_has_patch("lib/my_app_web/router.ex", """
    + | gust_dashboard()
    """)
  end

  test "configures dev database" do
    phoenix_project()
    |> Igniter.compose_task("gust.install")
    |> assert_has_patch("config/dev.exs", """
    + | config :gust, Gust.Repo,
    """)
    |> assert_has_patch("config/dev.exs", """
    + |  username: "postgres",
    """)
  end

  test "configures test mocks" do
    phoenix_project()
    |> Igniter.compose_task("gust.install")
    |> assert_has_patch("config/test.exs", """
    + |  dag_runner_supervisor: Gust.DAGRunnerSupervisorMock,
    """)
  end

  test "configures runtime prod" do
    phoenix_project()
    |> Igniter.compose_task("gust.install")
    |> assert_has_patch("config/runtime.exs", """
    + | config :gust, Gust.Repo, url: System.fetch_env!("DATABASE_URL")
    """)
    |> assert_has_patch("config/runtime.exs", """
    + | config :gust, b64_secrets_cloak_key: System.fetch_env!("B64_SECRETS_CLOAK_KEY")
    """)
  end

  test "skips duplicate router import" do
    test_project(
      app_name: :my_app,
      files: %{
        "lib/my_app_web/router.ex" => """
        defmodule MyAppWeb.Router do
          use Phoenix.Router
          import GustWeb.DashboardRouter

          pipeline :browser do
            plug :accepts, ["html"]
          end

          scope "/", MyAppWeb do
            pipe_through :browser
          end
        end
        """,
        "config/config.exs" => "import Config\n",
        "config/dev.exs" => "import Config\n",
        "config/test.exs" => "import Config\n",
        "config/runtime.exs" => "import Config\n"
      }
    )
    |> Igniter.compose_task("gust.install")
    |> assert_has_patch("lib/my_app_web/router.ex", """
    + | gust_dashboard()
    """)
  end

  test "configures ecto repo and logger" do
    phoenix_project()
    |> Igniter.compose_task("gust.install")
    |> assert_has_patch("config/config.exs", """
    + | config :my_app, ecto_repos: [Gust.Repo]
    """)
    |> assert_has_patch("config/config.exs", """
    + | config :logger,
    """)
    |> assert_has_patch("config/config.exs", """
    + |  dag_logger: Gust.DAG.Logger.Database,
    """)
  end
end
