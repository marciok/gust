if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.GustWeb.Install do
    @moduledoc false
    @shortdoc "Installs \"gust_web\" into your project"

    @dags_dir "dags"

    use Igniter.Mix.Task

    alias Igniter.Code.{Common, Function}
    alias Igniter.Code.List, as: CodeList
    alias Igniter.Libs.Phoenix, as: PhoenixLib
    alias Igniter.Project.{Application, Config, Deps, Module}

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :gust_web,
        example: "mix igniter.install gust_web"
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      setup_gust(igniter)
    end

    defp setup_gust(igniter) do
      name = igniter |> Application.app_name()

      igniter
      |> install_deps()
      |> config_setup(name)
      |> dev_config(name)
      |> runtime_config()
      |> test_config()
      |> Igniter.create_new_file("dags/.keep", ".gitkeep", onexists: :skip)
      |> add_import(name)
      |> add_scope(name)
      |> final_notice()
    end

    defp install_deps(igniter) do
      igniter
      |> Deps.add_dep({:file_system, "~> 1.1", only: :dev})
      |> Deps.add_dep({:gust_web, "0.1.30"})
    end

    defp config_setup(igniter, name) do
      igniter
      |> configure_each("config.exs", [
        {:gust, [:app_name], name},
        {:gust, [:dag_logger], Gust.DAG.Logger.Database},
        {name, [:ecto_repos], [Gust.Repo], updater: &append_gust_repo/1},
        {:gust, [Gust.Repo, :migration_source], "gust_schema_migrations"},
        {:logger, [:backends], [:console, Gust.DAG.Logger.Database]},
        {:logger, [:default_formatter],
         [
           format: "\$time \$metadata[\$level] \$message\n",
           metadata: [:request_id, :task_id, :attempt]
         ]},
        {:gust, [:dags_folder], {:code, Path.join(File.cwd!(), @dags_dir)}},
        {:gust, [:file_reload_delay], 1_000},
        {:gust, [:dag_runner_supervisor], Gust.DAG.RunnerSupervisor.DynamicSupervisor},
        {:gust, [:dag_task_runner_supervisor], Gust.DAG.TaskRunnerSupervisor.DynamicSupervisor},
        {:gust, [:dag_stage_runner_supervisor], Gust.DAG.StageRunnerSupervisor.DynamicSupervisor},
        {:gust, [:dag_scheduler], Gust.DAG.Scheduler.Worker},
        {:gust, [:dag_loader], Gust.DAG.Loader.Worker},
        {:gust, [:dag_stage_runner], Gust.DAG.Runner.StageWorker},
        {:gust_web, [:dashboard_path], "/gust"}
      ])
    end

    defp dev_config(igniter, name) do
      database = "#{name}_dev"
      cloak_key = :crypto.strong_rand_bytes(32) |> Base.encode64()

      igniter
      |> configure_each("dev.exs", [
        {:gust, [Gust.Repo, :username], code(~s[System.get_env("PG_USER", "postgres")])},
        {:gust, [Gust.Repo, :password], code(~s[System.get_env("PG_PASSWORD", "postgres")])},
        {:gust, [Gust.Repo, :hostname], code(~s[System.get_env("PG_HOST", "localhost")])},
        {:gust, [Gust.Repo, :database], code(~s[System.get_env("PG_DATABASE", "#{database}")])},
        {:gust, [Gust.Repo, :pool_size], 10},
        {:gust, [Gust.Repo, :show_sensitive_data_on_connection_error], true},
        {:gust, [:b64_secrets_cloak_key], cloak_key},
        {:gust_web, [:basic_auth], true}
      ])
      |> Igniter.add_notice("""
      Postgres credentials default to postgres/postgres@localhost in dev.
      Override at runtime with PG_USER, PG_PASSWORD, PG_HOST, PG_DATABASE,
      or edit config/dev.exs directly.
      """)
    end

    defp runtime_config(igniter) do
      igniter
      |> configure_runtime_each(:prod, [
        {:gust, [Gust.Repo, :url], code(~s[System.fetch_env!("DATABASE_URL")])},
        {:gust, [:b64_secrets_cloak_key], code(~s[System.fetch_env!("B64_SECRETS_CLOAK_KEY")])}
      ])
    end

    defp test_config(igniter) do
      igniter
      |> configure_each("test.exs", [
        {:gust, [:dag_runner_supervisor], Gust.DAGRunnerSupervisorMock},
        {:gust, [:dag_task_runner_supervisor], Gust.DAGTaskRunnerSupervisorMock}
      ])
    end

    defp add_scope(igniter, name) do
      scope_code = """
        pipe_through [:browser]

        gust_dashboard()
      """

      PhoenixLib.add_scope(igniter, "/", scope_code, router: router_module(name))
    end

    defp add_import(igniter, name) do
      Module.find_and_update_module!(igniter, router_module(name), fn zipper ->
        if import_present?(zipper, GustWeb.DashboardRouter) do
          {:ok, zipper}
        else
          {:ok, Common.add_code(zipper, "import GustWeb.DashboardRouter", placement: :before)}
        end
      end)
    end

    defp import_present?(zipper, module) do
      case Common.move_to(zipper, &import?(&1, module)) do
        {:ok, _} -> true
        :error -> false
      end
    end

    defp import?(zipper, module) do
      Function.function_call?(zipper, :import, 1) &&
        Function.argument_equals?(zipper, 0, module)
    end

    defp router_module(name) do
      app_mod = name |> to_string() |> Macro.camelize()
      Elixir.Module.concat([app_mod <> "Web", "Router"])
    end

    defp configure_each(igniter, file, configs) do
      Enum.reduce(configs, igniter, fn
        {app, path, value}, igniter ->
          Config.configure(igniter, file, app, path, value)

        {app, path, value, opts}, igniter ->
          Config.configure(igniter, file, app, path, value, opts)
      end)
    end

    defp configure_runtime_each(igniter, env, configs) do
      Enum.reduce(configs, igniter, fn {app, path, value}, igniter ->
        Config.configure_runtime_env(igniter, env, app, path, value)
      end)
    end

    defp append_gust_repo(zipper) do
      CodeList.append_new_to_list(
        zipper,
        Sourceror.parse_string!("Gust.Repo")
      )
    end

    defp code(string) do
      {:code, Sourceror.parse_string!(string)}
    end

    defp final_notice(igniter) do
      Igniter.add_notice(igniter, """

      Gust installed. Next:

          mix ecto.create
          mix ecto.migrate
          mix phx.server

      Then open http://localhost:4000/gust.

      To change the dashboard mount path, update :dashboard_path in
      config.exs and the gust_dashboard call in your router to match.

      For prod, set DATABASE_URL and B64_SECRETS_CLOAK_KEY env vars.
      """)
    end
  end
end
