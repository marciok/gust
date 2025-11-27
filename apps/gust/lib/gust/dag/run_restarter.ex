defmodule Gust.DAG.RunRestarter do
  @moduledoc false

  @callback start_dag(integer()) :: term()
  @callback restart_run(Gust.Flows.Run.t()) :: :ok
  @callback restart_task(map(), Gust.Flows.Task.t()) :: :ok
  @callback restart_dags(%{integer() => {:ok, Gust.DAG.Definition.t()} | {:error, term()}}) :: :ok
  @callback restart_enqueued(integer()) :: :ok

  # coveralls-ignore-start
  def start_dag(dag_id), do: impl().start_dag(dag_id)
  def restart_run(run), do: impl().restart_run(run)
  def restart_task(graph, task), do: impl().restart_task(graph, task)
  def restart_dags(dags), do: impl().restart_dags(dags)
  def restart_enqueued(dag), do: impl().restart_enqueued(dag)

  defp impl, do: Application.get_env(:gust, :dag_run_restarter, Gust.DAG.RunRestarter.Worker)
  # coveralls-ignore-stop
end
