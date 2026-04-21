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
      dags = Igniter.create_new_file(igniter, "dags/.keep", "")
      name = igniter |> Igniter.Project.Application.app_name()

      igniter
      |> install_deps()
      |> config_setup(name)
      |> common_config("dev.exs")
      |> common_config("prod.exs")
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
      |> Config.configure("config.exs", :logger, [:backends], [
        :console,
        Gust.DAG.Logger.Database
      ])
      |> Config.configure("config.exs", :logger, [:default_formatter],
        format: "\$time \$metadata[\$level] \$message\n",
        metadata: [:request_id, :task_id, :attempt]
      )
    end

    defp common_config(igniter, filename) do
      igniter
      |> Config.configure(filename, :gust_web, [:basic_auth], true)
      |> Config.configure(
        filename,
        :gust,
        [:dags_folder],
        {:code, Path.join(File.cwd!(), "dags")}
      )
      |> Config.configure(
        filename,
        :gust,
        [:file_reload_delay],
        1_000
      )
      |> Config.configure(
        filename,
        :gust,
        [:dag_runner_supervisor],
        Gust.DAG.RunnerSupervisor.DynamicSupervisor
      )
      |> Config.configure(
        filename,
        :gust,
        [:dag_task_runner_supervisor],
        Gust.DAG.TaskRunnerSupervisor.DynamicSupervisor
      )
      |> Config.configure(
        filename,
        :gust,
        [:dag_stage_runner_supervisor],
        Gust.DAG.StageRunnerSupervisor.DynamicSupervisor
      )
      |> Config.configure(filename, :gust, [:dag_scheduler], Gust.DAG.Schedular.Worker)
      |> Config.configure(filename, :gust, [:dag_loader], Gust.DAG.Loader.Worker)
      |> Config.configure(filename, :gust, [:dag_stage_runner], Gust.DAG.Runner.StageWorker)
    end
  end
end
