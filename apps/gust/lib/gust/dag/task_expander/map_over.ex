defmodule Gust.DAG.TaskExpander.MapOver do
  @moduledoc false
  @behaviour Gust.DAG.TaskExpander

  alias Gust.Flows

  @impl true
  def expand_over([head | params_list], task, _run_id, create_fn) do
    {:ok, head_task} = Flows.update_task_map_index(task, 0)

    rest_task =
      Enum.with_index(params_list, fn params, map_index ->
        task_clone = create_fn.(task.name, map_index + 1)
        {:ok, {task_clone, params}}
      end)

    [{:ok, {head_task, head}}] ++ rest_task
  end

  @impl true
  def get_params(upstream_task_name, run_id) do
    case Flows.get_task_instances_by_name_run(upstream_task_name, run_id) do
      [] ->
        {:expand_task_error,
         %RuntimeError{message: "Task: #{upstream_task_name} not found on run: #{run_id}"}}

      [task] ->
        case task.result do
          %{"gust_task_items" => items} when is_list(items) ->
            {:expand_task, items}

          %{} ->
            {:expand_task_error,
             %RuntimeError{message: "Task: #{upstream_task_name} result is empty"}}
        end

      tasks ->
        {:expand_task, Enum.map(tasks, fn task -> task.result end)}
    end
  end
end
