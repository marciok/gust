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
  @callback reset_task(graph(), task()) :: term()
  @callback dispatch_run(run()) :: term()
  @callback dispatch_all_runs(term()) :: [term()]

  # coveralls-ignore-start
  @spec reset_run(run()) :: term()
  def reset_run(run), do: impl().reset_run(run)

  @spec reset_task(graph(), task()) :: term()
  def reset_task(graph, task), do: impl().reset_task(graph, task)

  @spec dispatch_run(run()) :: term()
  def dispatch_run(run), do: impl().dispatch_run(run)
  def dispatch_all_runs(dag_id), do: impl().dispatch_all_runs(dag_id)

  defp impl, do: Application.get_env(:gust, :dag_run_trigger, Gust.DAG.Run.Trigger.Requeue)
  # coveralls-ignore-stop
end
