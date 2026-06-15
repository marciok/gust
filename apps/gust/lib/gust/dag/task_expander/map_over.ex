defmodule Gust.DAG.TaskExpander.MapOver do
  @moduledoc false
  @behaviour Gust.DAG.TaskExpander

  alias Gust.Flows

  @impl true
  def expand_over([], _task, _run_id, _create_fn), do: []

  @impl true
  def expand_over([item | items], task, _run_id, create_fn) do
    head = normalize_params(item)
    {:ok, head_task} = Flows.update_task_mapping(task, 0, head)

    rest_task =
      Enum.with_index(items, fn item, map_index ->
        params = normalize_params(item)
        task_clone = create_fn.(task.name, map_index + 1)
        {:ok, task_clone} = Flows.update_task_mapping(task_clone, map_index + 1, params)
        {:ok, {task_clone, params}}
      end)

    [{:ok, {head_task, head}}] ++ rest_task
  end

  @impl true
  def collapse_each([head | tail]) do
    Enum.each(tail, fn task ->
      Flows.delete_task!(task)
    end)

    {:ok, head} = Flows.update_task_mapping(head, nil, %{})
    head
  end

  @impl true
  def get_params(upstream_task_name, run_id, map_index) do
    tasks = Flows.get_tasks_by_name(upstream_task_name, run_id)
    parse_params(tasks, upstream_task_name, map_index, run_id)
  end

  defp parse_params([], upstream_task_name, _map_index, run_id) do
    expand_error("Task: #{upstream_task_name} not found on run: #{run_id}")
  end

  defp parse_params([task], upstream_task_name, map_index, _run_id) do
    expand_params(task.result, map_index, upstream_task_name)
  end

  defp parse_params(tasks, upstream_task_name, map_index, _run_id) do
    Enum.map(tasks, & &1.result) |> expand_items(map_index, upstream_task_name)
  end

  defp expand_params(%{"gust_task_items" => items}, map_index, upstream_task_name)
       when is_list(items) do
    expand_items(items, map_index, upstream_task_name)
  end

  defp expand_params(%{}, _map_index, upstream_task_name) do
    expand_error("Task: #{upstream_task_name} result is empty")
  end

  defp expand_items(items, map_index, upstream_task_name) do
    params = Enum.map(items, &normalize_params/1)

    if map_index do
      fetch_params(params, map_index, upstream_task_name)
    else
      {:expand_task, params}
    end
  end

  defp expand_error(message) do
    {:expand_task_error, %RuntimeError{message: message}}
  end

  defp fetch_params(items, map_index, upstream_task_name) do
    case Enum.fetch(items, map_index) do
      {:ok, params} ->
        {:already_expanded, params}

      :error ->
        expand_error("Task: #{upstream_task_name} has no mapped result at index: #{map_index}")
    end
  end

  defp normalize_params(params) when is_map(params), do: params
  defp normalize_params(item), do: %{"item" => item}
end
