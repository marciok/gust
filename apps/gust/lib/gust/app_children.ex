defmodule Gust.AppChildren do
  @moduledoc """
  Builds the application child list for a given runtime role and environment.

  The `for_role/3` function returns a list of supervisors and workers based on:

  * the runtime role
  * the Mix environment (`test`, `dev`, `prod`)
  * the configured DAG folder

  In practice, roles are used with the broader release like this:

  * `"console"` loads DAG definitions and supporting runtime pieces, but does
    not execute DAG pooling because `Gust.Run.Pooler` and
    `Gust.DAG.Terminator.Worker` are not started
  * `"web"` is intended for the web-facing runtime: it loads DAG definitions for
    the UI, while DAG pooling remains disabled
  * `"core"` loads DAGs, skips the web application, and runs the DAG pool
  * `"single"` loads DAGs, runs the web application, and runs the DAG pool

  Within this module specifically, `"web"` contributes only the DAG loader
  worker outside `test`, while `"console"` contributes the loader, watcher,
  leader, and runner supervisors without the pooling workers.

  In `test`, DAG runtime pieces (pooler, leader, loader, watcher) are skipped.
  In `prod`, the file watcher is disabled. In `dev`, the watcher is enabled to
  reload DAGs on file changes.
  """

  def for_role("web", mix_env, dags_folder) do
    dag_loader_worker(mix_env, dags_folder)
  end

  def for_role("console", mix_env, dags_folder) do
    dag_loader_worker(mix_env, dags_folder)
  end

  def for_role(_role, mix_env, dags_folder) do
    []
    |> Kernel.++(dag_run_pooler(mix_env))
    |> Kernel.++(dag_loader_worker(mix_env, dags_folder))
    |> Kernel.++(dag_watcher(mix_env, dags_folder))
    |> Kernel.++(leader(mix_env))
    |> Kernel.++(runners())
  end

  defp dag_run_pooler("test"), do: []

  defp dag_run_pooler(_env) do
    [Gust.Run.Pooler, Gust.DAG.Terminator.Worker]
  end

  defp leader("test"), do: []

  defp leader(_env),
    do: [
      Gust.Leader,
      {DynamicSupervisor, strategy: :one_for_one, name: Gust.LeaderOnlySupervisor}
    ]

  defp dag_watcher("test", _folder), do: []
  defp dag_watcher("prod", _folder), do: []

  defp dag_watcher(_env, folder) do
    [
      {Gust.FileMonitor.Worker, %{dags_folder: folder, loader: dag_loader()}}
    ]
  end

  defp dag_loader_worker("test", _folder), do: []

  defp dag_loader_worker(_env, folder) do
    [
      {Gust.DAG.Loader.Worker, %{dags_folder: folder}}
    ]
  end

  defp runners do
    [:dag_runner_supervisor, :dag_stage_runner_supervisor, :dag_task_runner_supervisor]
    |> Enum.map(fn supervisor ->
      {DynamicSupervisor, strategy: :one_for_one, name: Application.get_env(:gust, supervisor)}
    end)
  end

  defp dag_loader, do: Application.get_env(:gust, :dag_loader)
end
