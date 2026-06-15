defmodule Gust.DAG.Run.Trigger.Requeue do
  @moduledoc """
  Resets tasks and runs, then re-queues them for execution.

  Provides helpers to reset an entire run or a downstream branch of tasks, update
  run status to `:enqueued`, and broadcast the corresponding PubSub events. It
  also handles dispatching runs when the DAG is enabled.
  """

  alias Gust.DAG.Graph
  alias Gust.DAG.TaskExpander
  alias Gust.Flows
  alias Gust.PubSub

  @behaviour Gust.DAG.Run.Trigger

  @impl true
  def reset_run(run) do
    Flows.get_run_with_tasks!(run.id)
    |> then(fn run -> run.tasks end)
    |> Enum.each(fn task ->
      tasks = Flows.get_tasks_by_name(task.name, run.id)
      reset_all!(tasks)
    end)

    update_broadcast(run)
  end

  @impl true
  def reset_task(graph, task, map_index \\ nil) do
    run_id = task.run_id

    cleared_tasks =
      tasks_to_clear(graph, task.name)
      |> Enum.map(fn task_name ->
        if map_index && task_name == task.name do
          task = Flows.get_task_by_name(task_name, run_id, map_index)
          set_created!(task)
        else
          tasks = Flows.get_tasks_by_name(task_name, run_id)
          reset_all!(tasks)
        end
      end)

    run = Flows.get_run!(run_id)
    update_broadcast(run)
    cleared_tasks
  end

  defp tasks_to_clear(graph, starting_at) do
    graph
    |> Graph.build_branch(:downstream, starting_at)
    |> List.flatten()
    |> MapSet.new()
  end

  defp reset_all!([task]) do
    set_created!(task)
  end

  defp reset_all!(tasks) do
    task = TaskExpander.collapse_each(tasks)
    set_created!(task)
  end

  defp update_broadcast(run) do
    {:ok, run} = Flows.update_run_status(run, :enqueued)
    PubSub.broadcast_run_status(run.id, :enqueued)
    run
  end

  @impl true
  def dispatch_all_runs(dag_id) do
    Flows.get_running_runs_by_dag([dag_id], [:created])
    |> Enum.map(fn run ->
      {:ok, run} = Flows.update_run_status(run, :enqueued)
      run
    end)
  end

  @impl true
  def dispatch_run(run) do
    maybe_dispatch_enabled_dag(run, Flows.get_dag!(run.dag_id))
  end

  defp maybe_dispatch_enabled_dag(run, %Flows.Dag{enabled: false}), do: run

  defp maybe_dispatch_enabled_dag(run, %Flows.Dag{enabled: true}) do
    run = update_broadcast(run)
    PubSub.broadcast_run_dispatch(run.id)
    run
  end

  defp set_created!(task) do
    {:ok, task} = Flows.update_task_status(task, :created)
    task
  end
end
