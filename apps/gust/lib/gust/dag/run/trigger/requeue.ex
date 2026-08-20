defmodule Gust.DAG.Run.Trigger.Requeue do
  @moduledoc """
  Resets tasks and runs, then re-queues them for execution.

  Provides helpers to reset an entire run or a downstream branch of tasks, update
  run status to `:enqueued`, and broadcast the corresponding PubSub events. It
  also handles dispatching runs when the DAG is enabled.
  """

  alias Gust.DAG.Graph
  alias Gust.DAG.Runner.RunGateway
  alias Gust.DAG.TaskExpander
  alias Gust.Flows
  alias Gust.Run.Dispatcher

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
  def reset_task(graph, [%Flows.Task{} = task | _tasks]), do: call_restart(graph, task, :group)
  def reset_task(graph, %Flows.Task{map_index: nil} = task), do: call_restart(graph, task, :group)
  def reset_task(graph, %Flows.Task{} = task), do: call_restart(graph, task, :instance)

  defp call_restart(graph, task, type) do
    run = Flows.get_run!(task.run_id)

    message =
      case type do
        :group ->
          {:restart_task_group, task.name}

        :instance ->
          {:restart_task, task.id}
      end

    case RunGateway.call(run, message) do
      {:error, :run_not_active} -> reset_and_enqueue(graph, run, task, type)
      result -> result
    end
  end

  defp reset_and_enqueue(graph, run, task, scope) do
    cleared_tasks =
      graph
      |> tasks_to_clear(task.name)
      |> Enum.map(fn task_name -> reset_task_name(task_name, task, run.id, scope) end)

    update_broadcast(run)
    cleared_tasks
  end

  defp reset_task_name(task_name, task, _run_id, :instance) when task_name == task.name do
    set_created!(task)
  end

  defp reset_task_name(task_name, _task, run_id, _scope) do
    task_name
    |> Flows.get_tasks_by_name(run_id)
    |> reset_all!()
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
    Dispatcher.enqueue(run)
  end

  @impl true
  def dispatch_all_runs(dag_id) do
    Flows.get_running_runs_by_dag([dag_id], [:created])
    |> Dispatcher.enqueue_all()
  end

  @impl true
  def dispatch_run(run) do
    maybe_dispatch_enabled_dag(run, Flows.get_dag!(run.dag_id))
  end

  defp maybe_dispatch_enabled_dag(run, %Flows.Dag{enabled: false}), do: run

  defp maybe_dispatch_enabled_dag(run, %Flows.Dag{enabled: true}) do
    update_broadcast(run)
  end

  defp set_created!(task) do
    {:ok, task} = Flows.update_task_status(task, :created)
    task
  end
end
