# TODO: Rename to RetryingTask
defmodule Gust.DAG.StageCoordinator.RetryingRunner do
  @moduledoc false
  alias Gust.DAG.TaskDelayer
  alias Gust.Flows
  @behaviour Gust.DAG.StageCoordinator

  alias __MODULE__, as: Coord

  defstruct running: MapSet.new(), retrying: %{}

  def new(pending_task_ids), do: %Coord{running: MapSet.new(pending_task_ids)}

  def update_restart_timer(%{retrying: retrying} = coord, %{id: task_id}, ref) do
    updated_retrying =
      Map.update!(retrying, task_id, &Map.put(&1, :restart_timer, ref))

    %{coord | retrying: updated_retrying}
  end

  def process_task(%{status: :created, name: name, run_id: run_id}, tasks) do
    upstream_statuses =
      tasks[name][:upstream]
      |> Enum.map(&Flows.get_task_by_name_run(&1, run_id))
      |> Enum.map(& &1.status)

    if any_upstream_failed?(upstream_statuses), do: :upstream_failed, else: :ok
  end

  def process_task(%{status: status}, _tasks) when status in [:retrying], do: :ok

  def process_task(%{status: status}, _tasks)
      when status in [:succeeded, :failed, :upstream_failed],
      do: :already_processed

  def put_running(%{running: running} = coord, task_id) do
    %{coord | running: MapSet.put(running, task_id)}
  end

  def apply_task_result(coord, task, :upstream_failed), do: coord |> remove_pending_task(task)
  def apply_task_result(coord, task, :ok), do: coord |> remove_pending_task(task)
  def apply_task_result(coord, task, :already_processed), do: coord |> remove_pending_task(task)
  def apply_task_result(coord, task, :cancelled), do: coord |> remove_pending_task(task)

  def apply_task_result(%Coord{running: _running, retrying: retrying} = coord, task, :error) do
    task_id = task.id

    if retrying[task_id][:attempt] == 3 do
      fail_task(coord, task, task_id)
    else
      retry_task(coord, task, task_id)
    end
  end

  defp remove_pending_task(%Coord{running: running, retrying: retrying} = coord, task) do
    task_id = task.id

    coord_status(%{
      coord
      | running: MapSet.delete(running, task_id),
        retrying: Map.delete(retrying, task_id)
    })
  end

  defp any_upstream_failed?(upstream_tasks) do
    Enum.any?(upstream_tasks, fn status -> status in [:failed, :upstream_failed] end)
  end

  defp coord_status(coord), do: {if(any_running?(coord), do: :continue, else: :finished), coord}

  defp fail_task(%{running: running, retrying: retrying} = coord, task, task_id) do
    retrying = Map.delete(retrying, task.id)

    coord_status(%{
      coord
      | running: MapSet.delete(running, task_id),
        retrying: retrying
    })
  end

  defp retry_task(%Coord{running: running, retrying: retrying} = coord, task, task_id) do
    retrying =
      Map.update(retrying, task.id, %{attempt: 1}, fn %{attempt: attempt_num} ->
        %{attempt: attempt_num + 1}
      end)

    delay = TaskDelayer.calc_delay(task.attempt)

    {:reschedule, %{coord | running: MapSet.delete(running, task_id), retrying: retrying}, task,
     delay}
  end

  defp any_running?(%Coord{running: running, retrying: retrying}) do
    not Enum.empty?(running) or map_size(retrying) > 0
  end
end
