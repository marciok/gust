defmodule GustWeb.DagLive.Dashboard.MappedTasks do
  @moduledoc false

  alias Gust.DAG.MappedTasks, as: Limits
  alias Gust.DAG.TaskStatus
  alias GustWeb.Pagination

  def paging(tasks, status, requested_page) do
    case Limits.page_size(length(tasks)) do
      nil -> nil
      size -> build_paging(tasks, status, requested_page, size)
    end
  end

  def visible(tasks, status, nil), do: filter(tasks, status)

  def visible(tasks, status, %{size: size, page: page}) do
    tasks
    |> filter(status)
    |> Enum.slice((page - 1) * size, size)
  end

  def selected_ids(tasks, params) do
    valid_ids = tasks |> Enum.map(& &1.id) |> MapSet.new()

    params
    |> Map.get("task_ids", [])
    |> Enum.map(&String.to_integer/1)
    |> Enum.filter(&MapSet.member?(valid_ids, &1))
    |> Enum.uniq()
  end

  def select(tasks, selected_ids) do
    selected_ids = MapSet.new(selected_ids)
    Enum.filter(tasks, &MapSet.member?(selected_ids, &1.id))
  end

  def filter(tasks, ""), do: tasks
  def filter(tasks, status), do: Enum.filter(tasks, &(to_string(&1.status) == status))

  def cancelable?(tasks, selected_ids),
    do: eligible?(tasks, selected_ids, &TaskStatus.mapped_cancellable?/1)

  def restartable?(tasks, selected_ids),
    do: eligible?(tasks, selected_ids, &TaskStatus.restartable?/1)

  def restartable?(tasks), do: Enum.any?(tasks, &TaskStatus.restartable?(&1.status))

  defp build_paging(tasks, status, requested_page, size) do
    total = tasks |> filter(status) |> length() |> Pagination.total_pages(size)
    running = if status == "", do: running_page(tasks, size)
    page = requested_page || default_page(tasks, status, size, total)

    %{size: size, total: total, page: min(page, total), running: running}
  end

  defp running_page(tasks, size) do
    case indexes_with_status(tasks, [:running, :retrying]) do
      [] -> nil
      active -> active |> Enum.max() |> page_of(size)
    end
  end

  defp default_page(tasks, "", size, total) do
    running_page(tasks, size) || first_pending_page(tasks, size) || total
  end

  defp default_page(_tasks, _status, _size, _total), do: 1

  defp first_pending_page(tasks, size) do
    case indexes_with_status(tasks, [:created, :waiting]) do
      [] -> nil
      pending -> pending |> Enum.min() |> page_of(size)
    end
  end

  defp indexes_with_status(tasks, statuses) do
    for %{status: status, map_index: map_index} <- tasks, status in statuses, do: map_index
  end

  defp page_of(map_index, size), do: div(map_index, size) + 1

  defp eligible?(tasks, selected_ids, status_predicate) do
    tasks
    |> select(selected_ids)
    |> Enum.any?(&status_predicate.(&1.status))
  end
end
