defmodule Gust.DAG.Runner.TaskPager do
  @moduledoc false

  alias Gust.DAG.MappedTasks

  defstruct groups: %{}, task_groups: %{}, queued: MapSet.new()

  def new(stage) do
    pager =
      stage
      |> Enum.filter(fn {_status, task} -> not is_nil(task.map_index) end)
      |> Enum.group_by(fn {_status, task} -> task.name end)
      |> Enum.reduce(%__MODULE__{}, &add_group/2)

    {pager, Enum.reject(stage, fn {_status, task} -> queued?(pager, task.id) end)}
  end

  def queued?(%__MODULE__{queued: queued}, task_id), do: MapSet.member?(queued, task_id)

  def drop(%__MODULE__{queued: queued} = pager, task_id) do
    %{pager | queued: MapSet.delete(queued, task_id)}
  end

  def settle(%__MODULE__{} = pager, task_id) do
    name = pager.task_groups[task_id]
    group = pager.groups[name]

    if group && MapSet.member?(group.active, task_id) do
      release(pager, name, group, task_id)
    else
      {pager, []}
    end
  end

  defp add_group({name, entries}, pager) do
    case MappedTasks.page_size(length(entries)) do
      nil -> pager
      size -> put_group(pager, name, startable_ids(entries), size)
    end
  end

  defp startable_ids(entries) do
    entries
    |> Enum.sort_by(fn {_status, task} -> task.map_index end)
    |> Enum.flat_map(fn
      {:ok, task} -> [task.id]
      _entry -> []
    end)
  end

  defp put_group(pager, name, ids, size) do
    {active, pending} = Enum.split(ids, size)

    %{
      pager
      | groups: Map.put(pager.groups, name, group(active, pending, size)),
        task_groups: Enum.reduce(ids, pager.task_groups, &Map.put(&2, &1, name)),
        queued: Enum.into(pending, pager.queued)
    }
  end

  defp release(pager, name, group, task_id) do
    active = MapSet.delete(group.active, task_id)

    if MapSet.size(active) == 0 do
      next_page(pager, name, group)
    else
      {put_in(pager.groups[name], %{group | active: active}), []}
    end
  end

  defp next_page(pager, name, group) do
    {page, pending} =
      group.pending
      |> Enum.filter(&queued?(pager, &1))
      |> Enum.split(group.size)

    pager = %{
      pager
      | groups: Map.put(pager.groups, name, group(page, pending, group.size)),
        queued: MapSet.difference(pager.queued, MapSet.new(page))
    }

    {pager, page}
  end

  defp group(active, pending, size) do
    %{active: MapSet.new(active), pending: pending, size: size}
  end
end
