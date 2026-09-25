defmodule GustShell.TaskWorker.Adapter do
  @moduledoc """
  A `Gust.DAG.TaskWorker` that runs a DAG task as a shell command.

  The task's command and execution options are prepared by the parser
  and executed via `:exec.run/2`. Output
  is captured incrementally from `:stdout`/`:stderr` messages, and the
  worker reports the task result back to its owner once the OS process
  exits (`:DOWN`), translating non-zero exit codes and signals into
  `GustShell.ShellExitError`.
  """

  use Gust.DAG.TaskWorker

  alias Gust.DAG.Logger, as: DagLogger
  alias GustShell.Template

  @impl true
  def handle_info(:run, %{task: task, opts: %{run: command, exec_opts: exec_opts}} = state) do
    DagLogger.set_task(task.id, task.attempt)

    case render(command, exec_opts, task) do
      {:ok, command, exec_opts} -> start(command, exec_opts, state)
      {:error, error} -> send_task_error(state, error)
    end
  end

  def handle_info({:stdout, os_pid, data}, %{os_pid: os_pid} = state) do
    {:noreply, %{state | stdout: append_output(state.stdout, data)}}
  end

  @doc """
  Ignores stdout from mismatched PIDs.
  """
  def handle_info({:stdout, _other_pid, _data}, state) do
    {:noreply, state}
  end

  def handle_info({:stderr, os_pid, data}, %{os_pid: os_pid} = state) do
    {:noreply, %{state | stderr: append_output(state.stderr, data)}}
  end

  @doc """
  Ignores stderr from mismatched PIDs.
  """
  def handle_info({:stderr, _other_pid, _data}, state) do
    {:noreply, state}
  end

  def handle_info({:DOWN, os_pid, :process, _pid, reason}, %{os_pid: os_pid} = state) do
    {status, result} = finalize_task(state, reason)

    DagLogger.unset()
    send(state.owner_pid, {:task_result, result, state.task.id, status})

    {:stop, :normal, state}
  end

  @doc """
  Ignores DOWN messages from mismatched PIDs.
  """
  def handle_info({:DOWN, _other_pid, :process, _pid, _reason}, state) do
    {:noreply, state}
  end

  def handle_cast({:kill}, %{os_pid: os_pid} = state) do
    :exec.stop(os_pid)
    {:stop, :normal, state}
  end

  defp start(command, exec_opts, %{task: task} = state) do
    case :exec.run(command, exec_opts) do
      {:ok, _exec_pid, pid} ->
        {:noreply, Map.merge(state, %{os_pid: pid, stdout: [], stderr: []})}

      {:error, reason} ->
        error =
          RuntimeError.exception("failed to start shell task (#{task.id}): #{inspect(reason)}")

        send_task_error(state, error)
    end
  end

  defp render(command, exec_opts, task) do
    exec_opts =
      Enum.map(exec_opts, fn
        {:env, env} -> {:env, Enum.map(env, fn {key, value} -> {key, Template.render(value, task)} end)}
        option -> option
      end)

    {:ok, Template.render(command, task), exec_opts}
  rescue
    error ->
      {:error,
       RuntimeError.exception("failed to render shell task template: #{Exception.message(error)}")}
  end

  defp finalize_task(%{stdout: stdout, stderr: stderr}, reason) do
    output = %{stdout: flatten(stdout), stderr: flatten(stderr)}

    case reason do
      :normal ->
        {:ok, Map.put(output, :exit_code, 0) |> Map.put(:status, :success)}

      {:exit_status, 0} ->
        {:ok, Map.put(output, :exit_code, 0) |> Map.put(:status, :success)}

      {:exit_status, code} ->
        case :exec.status(code) do
          {:status, code} ->
            {:error,
             %GustShell.ShellExitError{
               exit_code: code,
               stdout: output.stdout,
               stderr: output.stderr
             }}

          {:signal, code, coredump} ->
            {:error,
             %GustShell.ShellExitError{
               exit_code: code,
               stdout: output.stdout,
               stderr: output.stderr,
               coredump: coredump
             }}
        end

      {:signal, signal, coredump} ->
        {:error,
         %GustShell.ShellExitError{
           exit_code: signal,
           stdout: output.stdout,
           stderr: output.stderr,
           coredump: coredump
         }}
    end
  end

  defp send_task_error(%{task: task, owner_pid: owner_pid} = state, error) do
    DagLogger.unset()
    send(owner_pid, {:task_result, error, task.id, :error})
    {:stop, error, state}
  end

  defp append_output(nil, chunk), do: [chunk]
  defp append_output(output, chunk) when is_binary(output), do: [output, chunk]
  defp append_output(output, chunk) when is_list(output), do: [output, chunk]

  defp flatten(nil), do: ""
  defp flatten(output) when is_binary(output), do: output
  defp flatten(output) when is_list(output), do: IO.iodata_to_binary(output)
end
