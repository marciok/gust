defmodule GustWeb.DagLive.Dashboard.TaskActions do
  @moduledoc false

  alias Gust.DAG.Run.Trigger
  alias Gust.DAG.TaskStatus
  alias Gust.DAG.Terminator
  alias Gust.Flows
  alias Gust.Flows.Task

  def reload(%Task{id: id}), do: Flows.get_task!(id)

  def filter(tasks, behaviour) do
    tasks
    |> Enum.map(&reload/1)
    |> Enum.filter(fn task -> apply(TaskStatus, behaviour, [task.status]) end)
  end

  def cancel(%Task{name: name, status: status} = task) do
    if TaskStatus.cancellable?(status) do
      case Terminator.cancel(task) do
        {:ok, _task} -> {:info, "Task: #{name} was cancelled"}
        {:error, reason} -> {:error, "Task: #{name} could not be cancelled: #{reason}"}
      end
    else
      {:info, "Task: #{name} is not running"}
    end
  end

  def cancel_many(tasks), do: aggregate_result(tasks, &cancel/1, "canceled")

  def restart(dag_def_tasks, %Task{name: name, map_index: map_index} = task) do
    result = Trigger.reset_task(dag_def_tasks, task)
    restart_flash(result, name, map_index)
  end

  def restart_many(dag_def_tasks, tasks),
    do: aggregate_result(tasks, &restart(dag_def_tasks, &1), "restarted")

  def restart_group(dag_def_tasks, [%Task{name: name} | _tasks] = tasks) do
    result = Trigger.reset_task(dag_def_tasks, tasks)
    restart_flash(result, name)
  end

  def restart_flash(result, name, map_index \\ nil) do
    case result do
      {:ok, _task} ->
        description = if is_nil(map_index), do: name, else: "#{name} [#{map_index}]"
        {:info, "Task: #{description} was restarted"}

      {:error, reason} ->
        {:error, "Task: #{name} could not be restarted: #{reason}"}
    end
  end

  defp aggregate_result([], _action, _verb), do: nil

  defp aggregate_result(tasks, action, verb) do
    %{ok: ok_tasks, error: error_tasks} =
      Enum.reduce(tasks, %{ok: 0, error: 0}, fn task, acc ->
        case action.(task) do
          {:info, _message} ->
            %{acc | ok: acc[:ok] + 1}

          {:error, _message} ->
            %{acc | error: acc[:error] + 1}
        end
      end)

    if error_tasks > 0 do
      {:error, "#{error_tasks} tasks could not be #{verb}"}
    else
      {:info, "#{ok_tasks} tasks #{verb}"}
    end
  end
end
