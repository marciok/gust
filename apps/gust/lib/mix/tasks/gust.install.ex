if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.Gust.Install do
    @shortdoc "Installs \"gust\" into your project"

    @dags_dir "dags"

    use Igniter.Mix.Task

    alias Igniter.Project.Deps
    alias Igniter.Project.Config

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :gust,
        example: "mix igniter.install gust"
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      setup_gust(igniter)
    end

    defp setup_gust(igniter) do
      name = igniter |> Igniter.Project.Application.app_name()

      igniter
      |> install_deps()
      |> config_setup(name)
      |> dev_config(name)
      |> runtime_config(name)
      |> test_config(name)
      |> Igniter.create_new_file("dags/.keep", ".gitkeep", onexists: :skip)
      |> Igniter.Project.Formatter.import_dep(:gust_web)
      |> add_import(name)
      |> add_scope(name)
      |> final_notice()
    end

    defp install_deps(igniter) do
      igniter
      |> Deps.add_dep({:plug_cowboy, "~> 2.7", only: :prod})
      |> Deps.add_dep({:hackney, "~> 1.9"})
      |> Deps.add_dep({:file_system, "~> 1.1", only: :dev})
      |> Deps.add_dep({:gust_web, "0.1.29"})
    end

    defp config_setup(igniter, name) do
      igniter
      |> Config.configure("config.exs", :gust, [:app_name], name)
      |> Config.configure("config.exs", :gust, [:dag_logger], Gust.DAG.Logger.Database)
      |> Config.configure(
        "config.exs",
        name,
        [:ecto_repos],
        [Gust.Repo],
        updater: fn zipper ->
          Igniter.Code.List.append_new_to_list(
            zipper,
            Sourceror.parse_string!("Gust.Repo")
          )
        end
      )
      |> Config.configure("config.exs", :logger, [:backends], [
        :console,
        Gust.DAG.Logger.Database
      ])
      |> Config.configure("config.exs", :logger, [:default_formatter],
        format: "\$time \$metadata[\$level] \$message\n",
        metadata: [:request_id, :task_id, :attempt]
      )
      |> Config.configure(
        "config.exs",
        :gust,
        [:dags_folder],
        {:code, Path.join(File.cwd!(), @dags_dir)}
      )
      |> Config.configure(
        "config.exs",
        :gust,
        [:file_reload_delay],
        1_000
      )
      |> Config.configure(
        "config.exs",
        :gust,
        [:dag_runner_supervisor],
        Gust.DAG.RunnerSupervisor.DynamicSupervisor
      )
      |> Config.configure(
        "config.exs",
        :gust,
        [:dag_task_runner_supervisor],
        Gust.DAG.TaskRunnerSupervisor.DynamicSupervisor
      )
      |> Config.configure(
        "config.exs",
        :gust,
        [:dag_stage_runner_supervisor],
        Gust.DAG.StageRunnerSupervisor.DynamicSupervisor
      )
      |> Config.configure("config.exs", :gust, [:dag_scheduler], Gust.DAG.Scheduler.Worker)
      |> Config.configure("config.exs", :gust, [:dag_loader], Gust.DAG.Loader.Worker)
      |> Config.configure("config.exs", :gust, [:dag_stage_runner], Gust.DAG.Runner.StageWorker)
    end

    defp dev_config(igniter, name) do
      database = "#{name}_dev"
      cloak_key = :crypto.strong_rand_bytes(32) |> Base.encode64()

      igniter
      |> Config.configure("dev.exs", :gust, [Gust.Repo, :username], "postgres")
      |> Config.configure("dev.exs", :gust, [Gust.Repo, :password], "postgres")
      |> Config.configure("dev.exs", :gust, [Gust.Repo, :hostname], "localhost")
      |> Config.configure("dev.exs", :gust, [Gust.Repo, :database], database)
      |> Config.configure("dev.exs", :gust, [Gust.Repo, :pool_size], 10)
      |> Config.configure(
        "dev.exs",
        :gust,
        [Gust.Repo, :show_sensitive_data_on_connection_error],
        true
      )
      |> Config.configure("dev.exs", :gust, [:b64_secrets_cloak_key], cloak_key)
      |> Config.configure("dev.exs", :gust_web, [:basic_auth], true)
    end

    defp runtime_config(igniter, _name) do
      igniter
      |> Config.configure_runtime_env(
        :prod,
        :gust,
        [Gust.Repo, :url],
        {:code, Sourceror.parse_string!(~s[System.fetch_env!("DATABASE_URL")])}
      )
      |> Config.configure_runtime_env(
        :prod,
        :gust,
        [:b64_secrets_cloak_key],
        {:code, Sourceror.parse_string!(~s[System.fetch_env!("B64_SECRETS_CLOAK_KEY")])}
      )
    end

    defp test_config(igniter, _) do
      igniter
      |> Config.configure(
        "test.exs",
        :gust,
        [:dag_runner_supervisor],
        Gust.DAGRunnerSupervisorMock
      )
      |> Config.configure(
        "test.exs",
        :gust,
        [:dag_task_runner_supervisor],
        Gust.DAGTaskRunnerSupervisorMock
      )
    end

    defp add_scope(igniter, name) do
      scope_code = """
        pipe_through [:browser]

        gust_dashboard "/gust"
      """

      Igniter.Libs.Phoenix.add_scope(igniter, "/", scope_code, router: router_module(name))
    end

    defp add_import(igniter, name) do
      Igniter.Project.Module.find_and_update_module!(igniter, router_module(name), fn zipper ->
        if import_present?(zipper, GustWeb.DashboardRouter) do
          {:ok, zipper}
        else
          {:ok,
           Igniter.Code.Common.add_code(zipper, "import GustWeb.DashboardRouter",
             placement: :before
           )}
        end
      end)
    end

    defp import_present?(zipper, module) do
      case Igniter.Code.Common.move_to(zipper, &import?(&1, module)) do
        {:ok, _} -> true
        :error -> false
      end
    end

    defp import?(zipper, module) do
      Igniter.Code.Function.function_call?(zipper, :import, 1) &&
        Igniter.Code.Function.argument_equals?(zipper, 0, module)
    end

    defp router_module(name) do
      app_mod = name |> to_string() |> Macro.camelize()
      Module.concat([app_mod <> "Web", "Router"])
    end

    defp final_notice(igniter) do
      Igniter.add_notice(igniter, """

      Gust installed. Next:

          mix ecto.create
          mix ecto.migrate
          mix phx.server

      Then open http://localhost:4000/gust.

      For prod, set DATABASE_URL and B64_SECRETS_CLOAK_KEY env vars.
      """)
    end
  end
end
