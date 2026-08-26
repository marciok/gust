defmodule Gust.DAG.Runner.TaskExecution do
  @moduledoc false

  alias Gust.DAG.{
    Adapter,
    ErrorParser,
    TaskRunnerSupervisor,
    TaskWaiter,
    TaskWorker
  }

  alias Gust.DAG.Run.ErrorReporter.Worker, as: ErrorReporterWorker
  alias Gust.DAG.Runner.TaskFailureError
  alias Gust.Flows
  alias Gust.PubSub

  def start(task, dag_def, owner_pid) do
    task = TaskWaiter.clear_wait(task)
    task_opts = Map.fetch!(dag_def.tasks, task.name)

    case TaskRunnerSupervisor.start_child(task, dag_def, owner_pid, task_opts) do
      {:ok, _pid} -> {:ok, Flows.get_task!(task.id)}
      {:error, reason} -> {:error, reason}
    end
  end

  def cancel(task, dag_def) do
    case Registry.lookup(Gust.Registry, TaskWorker.registry_name(task)) do
      [{task_pid, _value}] ->
        dag_def.adapter
        |> Adapter.impl!(:runtime)
        |> then(& &1.kill(task_pid))

      [] ->
        {:error, :task_worker_not_found}
    end
  end

  def apply_result(dag_def, task_id, status, result) do
    task = Flows.get_task!(task_id)

    if status in [:error, :non_recoverable_error] do
      update_error(task, result)
    else
      maybe_update_result(task, dag_def.tasks, status, result)
    end
  end

  def maybe_report_error(task, status, error, dag_name)
      when status in [:error, :non_recoverable_error] do
    {error, stacktrace} = error_and_stacktrace(error)
    exception = TaskFailureError.exception_from_error(error)

    data = %{
      task_name: task.name,
      run_id: task.run_id,
      dag_name: dag_name
    }

    ErrorReporterWorker.report(exception, stacktrace, data)
  end

  def maybe_report_error(_task, _status, _error, _dag_name), do: :ok

  def finish(task, status) do
    case status do
      :ok -> update_status!(task, :succeeded)
      :error -> update_status!(task, :failed)
      :non_recoverable_error -> update_status!(task, :failed)
      :upstream_failed -> update_status!(task, :upstream_failed)
      :skipped -> update_status!(task, :skipped)
      :cancelled -> update_status!(task, :failed)
      :already_processed -> nil
    end
  end

  def fail_start(task, reason) do
    task = update_error(task, start_error(reason))
    finish(task, :non_recoverable_error)
    {:error, reason}
  end

  def update_status!(task, status) do
    {:ok, %Flows.Task{run_id: run_id, status: task_status, id: task_id} = task} =
      Flows.update_task_status(task, status)

    PubSub.broadcast_run_status(run_id, task_status, task_id)
    task
  end

  def aggregate_status(task_ids) do
    statuses = Flows.get_task_statuses(task_ids)

    cond do
      Enum.any?(statuses, &(&1 == :failed)) -> :error
      Enum.any?(statuses, &(&1 == :upstream_failed)) -> :upstream_failed
      statuses != [] and Enum.all?(statuses, &(&1 == :skipped)) -> :skipped
      true -> :ok
    end
  end

  def start_error(reason) do
    RuntimeError.exception("Task worker could not start: #{inspect(reason)}")
  end

  defp maybe_update_result(task, tasks, status, result) do
    if update_result?(tasks, task.name, status) do
      {:ok, updated_task} = Flows.update_task_result_error(task, result, %{})
      updated_task
    else
      {:ok, task} = Flows.update_task_error(task, %{})
      task
    end
  end

  defp update_error(task, error) do
    {:ok, updated_task} = Flows.update_task_error(task, ErrorParser.parse(error))
    updated_task
  end

  defp error_and_stacktrace({:error_with_stacktrace, error, stacktrace}),
    do: {error, stacktrace}

  defp error_and_stacktrace(error), do: {error, []}

  defp update_result?(tasks, name, :ok), do: tasks[name][:store_result]
  defp update_result?(_tasks, _name, _status), do: false
end
