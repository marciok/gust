defmodule Gust.DAG.Graph do
  @moduledoc false

  def build_branch(tasks, direction, name) do
    branch = tasks[name][direction]

    if branch == MapSet.new([]) do
      [name]
    else
      siblings = for sibling_name <- branch, do: build_branch(tasks, direction, sibling_name)
      [name | siblings]
    end
  end

  def to_stages(tasks) do
    {:ok, sort(tasks)}
  rescue
    e in Gust.DAG.Graph.CycleDection ->
      {:error, e}
  end

  def link_tasks(task_list) do
    downstreams = build_downstreams(task_list)
    upstreams = build_upstreams(downstreams)
    merge_streams(downstreams, upstreams)
  end

  defp build_downstreams(task_list) do
    Map.new(task_list, fn
      {name, opts} when is_list(opts) ->
        {to_string(name),
         opts |> Keyword.get(:downstream, []) |> Enum.map(&to_string/1) |> MapSet.new()}
    end)
  end

  defp build_upstreams(downstreams) do
    Enum.reduce(downstreams, %{}, fn {node, ds}, acc ->
      Enum.reduce(ds, acc, fn d, acc2 ->
        Map.update(acc2, to_string(d), MapSet.new([node]), &MapSet.put(&1, node))
      end)
    end)
  end

  defp merge_streams(downstreams, upstreams) do
    Map.new(downstreams, fn {node, ds} ->
      {node, %{downstream: ds, upstream: Map.get(upstreams, node, MapSet.new())}}
    end)
  end

  def sort(tasks, sorted \\ [])
  def sort(tasks, sorted) when map_size(tasks) == 0, do: sorted

  def sort(tasks, sorted) do
    {current_task_layer, next_tasks} =
      tasks |> Map.split_with(fn {_k, v} -> MapSet.size(v[:upstream]) == 0 end)

    layer_keys = Map.keys(current_task_layer)

    next_tasks =
      next_tasks
      |> Map.new(fn {k, v} ->
        removed_up = MapSet.difference(v[:upstream], MapSet.new(layer_keys))
        {k, %{v | upstream: removed_up}}
      end)

    if map_size(current_task_layer) == 0, do: raise(Gust.DAG.Graph.CycleDection)

    sort(next_tasks, sorted ++ [layer_keys])
  end
end
