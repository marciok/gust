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
    |> Enum.uniq_by(& &1.name)
    |> Enum.map(fn task ->
      task.name
      |> Flows.get_tasks_by_name(run.id)
      |> collapse_to_head!()
    end)
    |> Flows.update_tasks_status(:created)

    Dispatcher.enqueue(run)
  end

  @doc """
  Restarts a single task. A mapped instance is restarted as a batch of one
  through `reset_mapped_tasks/2`.
  """
  @impl true
  def reset_task(graph, %Flows.Task{map_index: nil} = task), do: reset_group(graph, task)

  def reset_task(graph, %Flows.Task{} = task) do
    case reset_mapped_tasks(graph, [task]) do
      {:ok, [result]} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Restarts every instance of a mapped task, along with its downstream branch.
  Rejected while the run is active.
  """
  @impl true
  def reset_task_group(graph, [%Flows.Task{} = task | _tasks]), do: reset_group(graph, task)

  @doc """
  Restarts one or more instances of the same mapped task as a single batch.

  An active run owner restarts every instance in one call. Without one, all
  instances and the downstream branch are reset together and the run is
  enqueued once, so the new worker consumes the whole selection in parallel.
  Returns one result per instance.
  """
  @impl true
  def reset_mapped_tasks(graph, [%Flows.Task{name: name, run_id: run_id} | _tasks] = tasks) do
    run = Flows.get_run!(run_id)

    case RunGateway.call(run, {:restart_mapped_tasks, Enum.map(tasks, & &1.id)}) do
      {:error, :run_not_active} ->
        restarted = graph |> requeue(run, name, tasks) |> Enum.filter(&(&1.name == name))
        {:ok, Enum.map(restarted, &{:ok, &1})}

      result ->
        result
    end
  end

  defp reset_group(graph, %Flows.Task{name: name, run_id: run_id}) do
    run = Flows.get_run!(run_id)

    case RunGateway.call(run, {:restart_task_group, name}) do
      {:error, :run_not_active} ->
        {:ok, requeue(graph, run, name, Flows.get_tasks_by_name(name, run.id))}

      result ->
        result
    end
  end

  defp requeue(graph, run, name, restarted_tasks) do
    cleared_tasks =
      graph
      |> tasks_to_clear(name)
      |> Enum.flat_map(fn
        ^name -> set_created!(restarted_tasks)
        task_name -> [task_name |> Flows.get_tasks_by_name(run.id) |> reset_all!()]
      end)

    Dispatcher.enqueue(run)
    cleared_tasks
  end

  defp tasks_to_clear(graph, starting_at) do
    graph
    |> Graph.build_branch(:downstream, starting_at)
    |> List.flatten()
    |> MapSet.new()
  end

  defp reset_all!(tasks) do
    tasks
    |> collapse_to_head!()
    |> set_created!()
  end

  defp collapse_to_head!([task]), do: task
  defp collapse_to_head!(tasks), do: TaskExpander.collapse_each(tasks)

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
    Dispatcher.enqueue(run)
  end

  defp set_created!(%Flows.Task{} = task) do
    {:ok, task} = Flows.update_task_status(task, :created)
    task
  end

  defp set_created!(tasks) when is_list(tasks) do
    Flows.update_tasks_status(tasks, :created)
  end
end
