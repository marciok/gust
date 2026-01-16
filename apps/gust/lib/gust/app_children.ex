defmodule Gust.AppChildren do
  @moduledoc false

  def for_role("web", mix_env, dags_folder) do
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
    [Gust.Run.Pooler]
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
