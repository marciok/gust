defmodule GustPy.TaskWorker.Adapter do
  @moduledoc false

  use Gust.DAG.TaskWorker
  require Logger

  alias Gust.DAG.Logger, as: DagLogger
  alias GustPy.TaskMessenger, as: Messenger
  alias GustPy.TaskWorker.Error

  @impl true
  def handle_info(:run, %{task: task, dag_def: dag_def} = state) do
    task_context = %{run_id: task.run_id}

    DagLogger.set_task(task.id, task.attempt)
    port = GustPy.Executor.start_task_via_port(dag_def, task.name, task_context)

    {:noreply, Map.put(state, :port, port)}
  end

  def handle_info({_port, {:data, data}}, state) do
    {:noreply, handle_port_data(state, data)}
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    state = handle_port_exit(state, status)

    DagLogger.unset()
    {:stop, :normal, state}
  end

  defp handle_port_data(state, data) do
    case GustPy.TaskMessenger.decode(data) do
      {:ok, msg} ->
        state |> handle_message(msg)

      {:error, error} ->
        Logger.warning("Failed to decode port message: #{Exception.message(error)}")
        state
    end
  end

  defp send_task_result(%{task: task, stage_pid: stage_pid} = state, result, status) do
    send(stage_pid, {:task_result, result, task.id, status})
    state
  end

  defp handle_message(%{port: port} = state, msg) do
    case Messenger.handle_next(msg) do
      {:reply, payload} ->
        Messenger.reply(port, payload)
        state

      {:done, done} ->
        Map.put(state, :done, done)

      :noreply ->
        state
    end
  end

  defp handle_port_exit(%{done: done} = state, 0) do
    case done do
      {:result, result} ->
        send_task_result(state, result, :ok)

      {:error, error} ->
        send_task_result(state, error, :error)
    end
  end

  defp handle_port_exit(state, status) do
    send_task_result(state, Error.new(:port_exit, "died with: #{status}"), :error)
  end
end
