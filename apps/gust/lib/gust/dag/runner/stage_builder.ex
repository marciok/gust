defmodule Gust.DAG.Runner.StageBuilder do
  @moduledoc false

  alias Gust.DAG.StageCoordinator, as: Coord
  alias Gust.DAG.TaskExpander
  alias Gust.Flows

  def build(stage_names, run_id, dag_def) do
    {:ok, tasks} = Flows.reconcile_run_tasks(stage_names, run_id)

    Enum.flat_map(tasks, fn {:ok, task} ->
      build_task(task, run_id, dag_def)
    end)
  end

  def task_ids(stage), do: for({_status, task} <- stage, do: task.id)

  defp build_task(task, run_id, dag_def) do
    case Coord.process_task(task, dag_def.tasks) do
      {:expand_task, []} ->
        [{:skipped, task}]

      {:expand_task, params_list} ->
        expand_task(task, run_id, params_list)

      {:expand_task_error, error} ->
        [{{:non_recoverable_error, error}, task}]

      {:already_expanded, params} ->
        {:ok, task} = Flows.update_task_mapping(task, task.map_index, params)
        [{:ok, task}]

      status ->
        [{status, task}]
    end
  end

  defp expand_task(task, run_id, params_list) do
    params_list
    |> TaskExpander.expand_over(task, run_id, fn task_name, index ->
      {:ok, task} = reconcile_mapped_task(task_name, run_id, index)
      task
    end)
    |> Enum.map(fn {status, {task, _params}} -> {status, task} end)
  end

  defp reconcile_mapped_task(name, run_id, map_index) do
    case Flows.get_task_by_name(name, run_id, map_index) do
      nil ->
        Flows.create_task(%{run_id: run_id, name: name, map_index: map_index})

      %Flows.Task{status: :running} = task ->
        Flows.update_task_status(task, :created)

      %Flows.Task{} = task ->
        {:ok, task}
    end
  end
end
