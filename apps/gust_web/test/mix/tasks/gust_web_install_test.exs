defmodule Mix.Tasks.GustWebInstallTest do
  use ExUnit.Case

  import Igniter.Test

  setup do
    project =
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

    %{project: project}
  end

  setup %{project: project} do
    %{igniter: Igniter.compose_task(project, "gust_web.install")}
  end

  def app_with_repo_proj(%{}) do
    project =
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

          config :my_app, ecto_repos: [MyApp.Repo]
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

    %{project: project}
  end

  def router_imported_proj(%{}) do
    project =
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

    %{igniter: Igniter.compose_task(project, "gust_web.install")}
  end

  test "installs into a phoenix project", %{igniter: igniter} do
    igniter
    |> assert_has_patch("config/config.exs", """
    + | config :gust_web, dashboard_path: "/gust"
    """)
    |> assert_has_patch("config/config.exs", """
    + |  app_name: :my_app,
    """)
    |> assert_creates("dags/.keep")
    |> assert_has_notice(&String.contains?(&1, "Gust installed"))
  end

  test "adds import and scope to router", %{igniter: igniter} do
    igniter
    |> assert_has_patch("lib/my_app_web/router.ex", """
    + | import GustWeb.DashboardRouter
    """)
    |> assert_has_patch("lib/my_app_web/router.ex", """
    + | gust_dashboard()
    """)
  end

  test "configures dev database", %{igniter: igniter} do
    igniter
    |> assert_has_patch("config/dev.exs", """
    + | config :gust, Gust.Repo,
    """)
    |> assert_has_patch("config/dev.exs", """
    + |  username: System.get_env("PG_USER", "postgres"),
    """)
    |> assert_has_patch("config/dev.exs", """
    + |  password: System.get_env("PG_PASSWORD", "postgres"),
    """)
    |> assert_has_patch("config/dev.exs", """
    + |  hostname: System.get_env("PG_HOST", "localhost"),
    """)
    |> assert_has_patch("config/dev.exs", """
    + |  database: System.get_env("PG_DATABASE", "my_app_dev"),
    """)
    |> assert_has_notice(&String.contains?(&1, "PG_USER"))
  end

  test "configures test mocks", %{igniter: igniter} do
    igniter
    |> assert_has_patch("config/test.exs", """
    + |  dag_runner_supervisor: Gust.DAGRunnerSupervisorMock,
    """)
  end

  test "configures runtime prod", %{igniter: igniter} do
    igniter
    |> assert_has_patch("config/runtime.exs", """
    + | config :gust, Gust.Repo, url: System.fetch_env!("DATABASE_URL")
    """)
    |> assert_has_patch("config/runtime.exs", """
    + | config :gust, b64_secrets_cloak_key: System.fetch_env!("B64_SECRETS_CLOAK_KEY")
    """)
  end

  test "configures ecto repo and logger", %{igniter: igniter} do
    igniter
    |> assert_has_patch("config/config.exs", """
    + | config :my_app, ecto_repos: [Gust.Repo]
    """)
    |> assert_has_patch("config/config.exs", """
    + | config :gust, Gust.Repo, migration_source: "gust_schema_migrations"
    """)
    |> assert_has_patch("config/config.exs", """
    + | config :logger,
    """)
    |> assert_has_patch("config/config.exs", """
    + |  dag_logger: Gust.DAG.Logger.Database,
    """)
  end

  describe "app already has a repo" do
    setup [:app_with_repo_proj]

    test "appends Gust.Repo to existing ecto_repos config", %{project: project} do
      project
      |> Igniter.compose_task("gust_web.install")
      |> assert_has_patch("config/config.exs", """
      + |config :my_app, ecto_repos: [MyApp.Repo, Gust.Repo]
      """)
    end
  end

  describe "app already imported DashboardRouter" do
    setup [:router_imported_proj]

    test "skips duplicate router import", %{igniter: igniter} do
      igniter
      |> assert_has_patch("lib/my_app_web/router.ex", """
      + | gust_dashboard()
      """)
    end
  end
end
