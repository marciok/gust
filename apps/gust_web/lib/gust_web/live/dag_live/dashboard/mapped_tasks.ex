defmodule GustWeb.DagLive.Dashboard.MappedTasks do
  @moduledoc false

  alias Gust.DAG.TaskStatus

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
    do: eligible?(tasks, selected_ids, &TaskStatus.cancellable?/1)

  def restartable?(tasks, selected_ids),
    do: eligible?(tasks, selected_ids, &TaskStatus.restartable?/1)

  def restartable?(tasks), do: Enum.any?(tasks, &TaskStatus.restartable?(&1.status))

  defp eligible?(tasks, selected_ids, status_predicate) do
    tasks
    |> select(selected_ids)
    |> Enum.any?(&status_predicate.(&1.status))
  end
end
