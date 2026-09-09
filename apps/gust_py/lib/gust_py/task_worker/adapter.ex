defmodule GustPy.TaskWorker.Adapter do
  @moduledoc false

  use Gust.DAG.TaskWorker
  require Logger

  alias Gust.DAG.Logger, as: DagLogger
  alias GustPy.Executor
  alias GustPy.TaskMessenger, as: Messenger
  alias GustPy.TaskMessenger.FrameCodec
  alias GustPy.TaskWorker.Error

  @impl true
  def handle_cast({:kill}, %{os_pid: os_pid} = state) do
    :exec.stop(os_pid)

    {:stop, :normal, state}
  end

  @impl true
  def handle_info(:run, %{task: task, dag_def: dag_def} = state) do
    task_context = task_context(task)

    DagLogger.set_task(task.id, task.attempt)
    os_pid = Executor.start_task(dag_def, task.name, task_context)

    {:noreply, state |> Map.put(:os_pid, os_pid) |> Map.put(:buffer, <<>>)}
  end

  def handle_info({:stdout, os_pid, data}, %{os_pid: os_pid} = state) do
    {:noreply, handle_stream_data(state, data)}
  end

  def handle_info({:stderr, os_pid, data}, %{os_pid: os_pid} = state) do
    Logger.warning(data)
    {:noreply, state}
  end

  def handle_info({:DOWN, os_pid, :process, _pid, reason}, %{os_pid: os_pid} = state) do
    state = handle_exit(state, reason)

    DagLogger.unset()
    {:stop, :normal, state}
  end

  defp task_context(%{map_index: nil} = task), do: %{run_id: task.run_id}

  defp task_context(task),
    do: %{run_id: task.run_id, params: task.params}

  defp handle_stream_data(%{buffer: buffer} = state, data) do
    {frames, remaining} = FrameCodec.decode(buffer, data)

    frames
    |> Enum.reduce(state, &handle_frame(&2, &1))
    |> Map.put(:buffer, remaining)
  end

  defp handle_frame(state, frame) do
    case GustPy.TaskMessenger.decode(frame) do
      {:ok, msg} ->
        state |> handle_message(msg)

      {:error, error} ->
        Logger.warning("Failed to decode task message: #{Exception.message(error)}")
        state
    end
  end

  defp send_task_result(%{task: task, owner_pid: owner_pid} = state, result, status) do
    send(owner_pid, {:task_result, result, task.id, status})
    state
  end

  defp handle_message(%{os_pid: os_pid} = state, msg) do
    case Messenger.handle_next(msg) do
      {:reply, payload} ->
        Messenger.reply(os_pid, payload)
        state

      {:done, done} ->
        Map.put(state, :done, done)

      :noreply ->
        state
    end
  end

  defp handle_exit(%{done: done} = state, reason) when reason in [:normal, {:exit_status, 0}] do
    case done do
      {:result, result} ->
        send_task_result(state, result, :ok)

      {:error, error} ->
        send_task_result(state, error, :error)
    end
  end

  defp handle_exit(state, reason) do
    send_task_result(state, Error.new(:process_exit, "died with: #{inspect(reason)}"), :error)
  end
end
