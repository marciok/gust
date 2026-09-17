defmodule GustWeb.DagLive.Dashboard.SelectedItem do
  @moduledoc false

  alias Gust.Flows
  alias Gust.Flows.Run
  alias Gust.Flows.Task
  alias Gust.PubSub

  @aggregate_status_precedence [
    :failed,
    :upstream_failed,
    :retrying,
    :running,
    :waiting,
    :enqueued,
    :created,
    :skipped,
    :succeeded
  ]

  def load(params) do
    params
    |> fetch()
    |> subscribe()
  end

  def attributes(item) do
    {inserted_at, updated_at} = timestamps(item)

    %{
      item_name: name(item),
      item_id: id(item),
      item_status: status(item),
      item_inserted_at: inserted_at,
      item_updated_at: updated_at,
      item_params: params(item),
      item_error: error(item),
      item_result: result(item)
    }
  end

  def expanded_items(tasks) when is_list(tasks), do: tasks
  def expanded_items(_item), do: []

  def expanded_ids(item), do: item |> expanded_items() |> Enum.map(& &1.id)

  def expanded(%Task{name: name, run_id: run_id, map_index: index}) when index != nil,
    do: Flows.get_tasks_by_name(name, run_id)

  def expanded(_item), do: []

  def status(nil), do: nil
  def status(%Task{status: status}), do: status
  def status(%Run{status: status}), do: status

  def status([%Task{} | _tail] = tasks) do
    statuses = tasks |> Enum.map(& &1.status) |> MapSet.new()
    Enum.find(@aggregate_status_precedence, &MapSet.member?(statuses, &1))
  end

  def logs(item, level \\ nil)
  def logs(nil, _level), do: []
  def logs(%Task{} = task, level), do: Flows.get_logs(task.id, level)
  def logs(%Run{}, _level), do: []
  def logs([%Task{} | _tail], _level), do: []

  def run_id(nil), do: nil
  def run_id(%Run{id: id}), do: id
  def run_id(%Task{run_id: run_id}), do: run_id
  def run_id([%Task{run_id: run_id} | _tail]), do: run_id

  def task_names(%Task{name: name}), do: [name]
  def task_names([%Task{name: name} | _tail]), do: [name]
  def task_names(_item), do: []

  def task_group_selected?(nil, _tasks), do: false

  def task_group_selected?([%Task{run_id: run_id, name: name} | _tail], tasks),
    do: same_task_group?(tasks, run_id, name)

  def task_group_selected?(%Task{run_id: run_id, name: name}, tasks),
    do: same_task_group?(tasks, run_id, name)

  def task_group_selected?(_item, _tasks), do: false

  defp fetch(%{"run_id" => run_id, "task_name" => task_name, "task_index" => task_index}),
    do: Flows.get_task_by_name(task_name, run_id, task_index)

  defp fetch(%{"run_id" => run_id, "task_name" => task_name}) do
    case Flows.get_tasks_by_name(task_name, run_id) do
      [] -> nil
      [task] when is_nil(task.map_index) -> task
      tasks -> tasks
    end
  end

  defp fetch(%{"run_id" => run_id}), do: Flows.get_run_with_tasks!(run_id)
  defp fetch(_params), do: nil

  defp subscribe(nil), do: nil

  defp subscribe(%Task{id: task_id} = task) do
    PubSub.subscribe_task(task_id)
    PubSub.subscribe_run(task.run_id)
    task
  end

  defp subscribe(%Run{id: run_id} = run) do
    PubSub.subscribe_run(run_id)
    run
  end

  defp subscribe([%Task{run_id: run_id} | _tail] = tasks) do
    PubSub.subscribe_run(run_id)
    tasks
  end

  defp name(nil), do: nil
  defp name(%Task{name: name, map_index: nil}), do: name
  defp name(%Task{name: name, map_index: index}), do: "#{name} [#{index}]"
  defp name(%Run{id: id}), do: "Run #{id}"
  defp name([%Task{name: name} | _tail]), do: "#{name} []"

  defp id(nil), do: nil
  defp id(%Task{id: id}), do: id
  defp id(%Run{id: id}), do: id
  defp id([%Task{} | _tail]), do: nil

  defp timestamps(nil), do: {nil, nil}

  defp timestamps(%Task{inserted_at: inserted_at, updated_at: updated_at}),
    do: {inserted_at, updated_at}

  defp timestamps(%Run{inserted_at: inserted_at, updated_at: updated_at}),
    do: {inserted_at, updated_at}

  defp timestamps([%Task{} | _tail]), do: {nil, nil}

  defp params(nil), do: nil
  defp params(%Task{params: params}), do: params
  defp params(%Run{params: params}), do: params
  defp params([%Task{} | _tail]), do: %{}

  defp error(nil), do: nil
  defp error(%Task{error: error}), do: error
  defp error(%Run{}), do: %{}
  defp error([%Task{} | _tail]), do: %{}

  defp result(nil), do: nil
  defp result(%Task{result: result}), do: result
  defp result(%Run{}), do: %{}
  defp result([%Task{} | _tail]), do: %{}

  defp same_task_group?(tasks, run_id, name),
    do: Enum.any?(tasks, &(&1.run_id == run_id and &1.name == name))
end
