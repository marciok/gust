defmodule GustWeb.DagLive.Dashboard.MappedTasks do
  @moduledoc false

  alias Gust.DAG.TaskStatus
  alias GustWeb.Pagination

  @default_page_size 50

  @doc """
  Pages the instances for display. Opens on the first page and only moves when
  a page is requested, so the table never shifts while instances progress.
  `running` marks the page of the furthest active instance.
  """
  def paging(tasks, status, requested_page) do
    size = page_size()

    if length(tasks) > size, do: build_paging(tasks, status, requested_page, size)
  end

  @doc """
  How many mapped instances the dashboard lists per page.

  Purely a display setting, independent from `:max_parallel`, which limits how
  many instances run at once. Configure with
  `config :gust_web, :mapped_task_page_size, 50`.
  """
  def page_size, do: Application.get_env(:gust_web, :mapped_task_page_size, @default_page_size)

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

  def all_selected?([], _selected_ids), do: false

  def all_selected?(tasks, selected_ids) do
    selected_ids = MapSet.new(selected_ids)
    Enum.all?(tasks, &MapSet.member?(selected_ids, &1.id))
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
    page = min(requested_page || 1, total)

    %{size: size, total: total, page: page, running: running}
  end

  defp running_page(tasks, size) do
    case indexes_with_status(tasks, [:running, :retrying]) do
      [] -> nil
      active -> active |> Enum.max() |> page_of(size)
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
