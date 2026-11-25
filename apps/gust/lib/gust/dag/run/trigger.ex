defmodule Gust.DAG.Run.Trigger do
  @moduledoc """
  Behaviour for triggering DAG run actions (reset/requeue/dispatch).

  This module delegates to the configured implementation module:

      config :gust, :dag_run_trigger, Gust.DAG.Run.Trigger.Requeue

  The configured module must implement this behaviour.
  """

  @type run :: term()
  @type task :: term()
  @type graph :: term()

  @callback reset_run(run()) :: term()
  @callback reset_task(graph(), task()) :: {:ok, task() | [task()]} | {:error, term()}
  @callback reset_task_group(graph(), [task()]) :: {:ok, [task()]} | {:error, term()}
  @callback reset_mapped_tasks(graph(), [task()]) ::
              {:ok, [{:ok, task()} | {:error, term()}]} | {:error, term()}
  @callback dispatch_run(run()) :: term()
  @callback dispatch_all_runs(term()) :: [term()]

  # coveralls-ignore-start
  @spec reset_run(run()) :: term()
  def reset_run(run), do: impl().reset_run(run)

  @spec reset_task(graph(), task()) :: {:ok, task() | [task()]} | {:error, term()}
  def reset_task(graph, task), do: impl().reset_task(graph, task)

  @spec reset_task_group(graph(), [task()]) :: {:ok, [task()]} | {:error, term()}
  def reset_task_group(graph, tasks), do: impl().reset_task_group(graph, tasks)

  @spec reset_mapped_tasks(graph(), [task()]) ::
          {:ok, [{:ok, task()} | {:error, term()}]} | {:error, term()}
  def reset_mapped_tasks(graph, tasks), do: impl().reset_mapped_tasks(graph, tasks)

  @spec dispatch_run(run()) :: term()
  def dispatch_run(run), do: impl().dispatch_run(run)
  def dispatch_all_runs(dag_id), do: impl().dispatch_all_runs(dag_id)

  defp impl, do: Application.get_env(:gust, :dag_run_trigger, Gust.DAG.Run.Trigger.Requeue)
  # coveralls-ignore-stop
end
