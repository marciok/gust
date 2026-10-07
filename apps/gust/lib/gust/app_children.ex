defmodule Gust.AppChildren do
  alias Gust.DAG.Source.Config

  @moduledoc """
  Builds the application child list for a given runtime role and environment.

  The `for_role/2` function returns a list of supervisors and workers based on:

  * the runtime role
  * the Mix environment (`test`, `dev`, `prod`)

  In practice, roles are used with the broader release like this:

  * `"console"` loads DAG definitions and supporting runtime pieces, but does
    not execute DAG dispatch because `Gust.Run.Claimer` is not started
  * `"web"` is intended for the web-facing runtime: it loads DAG definitions for
    the UI, while DAG pooling remains disabled
  * `"core"` loads DAGs, skips the web application, and dispatches DAG runs
  * `"single"` loads DAGs, runs the web application, and dispatches DAG runs

  Within this module specifically, `"web"` and `"console"` contribute the DAG
  loader worker and the source monitors outside `test`, so polling sources stay
  fresh on those nodes. Other roles add the dispatcher, leader, and runners.

  In `test`, DAG runtime pieces (dispatcher, leader, loader, watcher) are skipped.
  Source monitors (Git, Database, S3 polling) run in `dev` and `prod`; only the
  Folder source's OS file watcher is limited to `dev`.
  """

  def for_role(role, mix_env) when role in ["web", "console"] do
    dag_loader_worker(mix_env) ++ dag_watcher(mix_env)
  end

  def for_role(_role, mix_env) do
    []
    |> Kernel.++(dag_run_dispatcher(mix_env))
    |> Kernel.++(dag_loader_worker(mix_env))
    |> Kernel.++(dag_watcher(mix_env))
    |> Kernel.++(leader(mix_env))
    |> Kernel.++(runners())
  end

  defp dag_run_dispatcher("test"), do: []

  defp dag_run_dispatcher(_env) do
    [Gust.Run.DispatcherSupervisor]
  end

  defp leader("test"), do: []

  defp leader(_env),
    do: [
      Gust.Leader,
      {DynamicSupervisor, strategy: :one_for_one, name: Gust.LeaderOnlySupervisor}
    ]

  defp dag_watcher("test"), do: []

  defp dag_watcher(env) do
    Config.read()
    |> Enum.reject(&(env != "dev" and Config.source_module(&1) == Gust.DAG.Source.Folder))
    |> Enum.map(fn source ->
      id = Map.get(source, :id) || Map.get(source, "id")
      {Gust.FileMonitor.Worker, %{id: id, loader: dag_loader()}}
    end)
  end

  defp dag_loader_worker("test"), do: []
  defp dag_loader_worker(_env), do: [Gust.DAG.Loader.Worker]

  defp runners do
    [:dag_runner_supervisor, :dag_task_runner_supervisor]
    |> Enum.map(fn supervisor ->
      {DynamicSupervisor, strategy: :one_for_one, name: Application.get_env(:gust, supervisor)}
    end)
  end

  defp dag_loader, do: Application.get_env(:gust, :dag_loader)
end
