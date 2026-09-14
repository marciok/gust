defmodule Gust.DAG.TaskWorker.Adapters.Shell do
  @moduledoc false

  use Gust.DAG.TaskWorker

  alias Gust.DAG.Logger, as: DagLogger

  @impl true
  def handle_info(:run, %{task: task, dag_def: dag_def} = state) do
    case resolve_command(task, dag_def) do
      {:ok, command} ->
        DagLogger.set_task(task.id, task.attempt)

        case :exec.run(command, [
               :stdin,
               :stdout,
               :stderr,
               :monitor,
               {:group, 0},
               :kill_group,
               {:kill_timeout, 5}
             ]) do
          {:ok, _exec_pid, pid} ->
            {:noreply, %{state | os_pid: pid, stdout: [], stderr: []}}

          {:error, reason} ->
            error = RuntimeError.exception("failed to start shell task (#{task.id}): #{inspect(reason)}")
            send_task_error(state, error)
        end

      {:error, error} ->
        send_task_error(state, error)
    end
  end

  def handle_info({:stdout, os_pid, data}, %{os_pid: os_pid} = state) do
    {:noreply, %{state | stdout: append_output(state.stdout, data)}}
  end

  def handle_info({:stderr, os_pid, data}, %{os_pid: os_pid} = state) do
    {:noreply, %{state | stderr: append_output(state.stderr, data)}}
  end

  def handle_info({:DOWN, os_pid, :process, _pid, reason}, %{os_pid: os_pid} = state) do
    {status, result} = finalize_task(state, reason)

    DagLogger.unset()
    send(state.owner_pid, {:task_result, result, state.task.id, status})

    {:stop, :normal, state}
  end

  defp resolve_command(task, dag_def) do
    case Map.get(task.params, "command") || Map.get(task.params, :command) ||
           (dag_def && Map.get(dag_def, :command)) do
      nil ->
        {:error, RuntimeError.exception("shell task requires a command in task.params['command']")}

      command when is_binary(command) ->
        {:ok, command}

      command ->
        {:ok, to_string(command)}
    end
  end

  defp finalize_task(%{stdout: stdout, stderr: stderr}, reason) do
    output = %{stdout: flatten(stdout), stderr: flatten(stderr)}

    case reason do
      :normal ->
        {:ok, Map.put(output, :exit_code, 0) |> Map.put(:status, :success)}

      {:exit_status, 0} ->
        # This is an impossble case, so log it for troubleshooting :erlexec
        DagLogger.warning("shell task exited with status 0 but reason was not :normal")
        {:ok, Map.put(output, :exit_code, 0) |> Map.put(:status, :success)}

      {:exit_status, code} ->
        case :exec.status(code) do
          {:status, code} ->
            {:error,
             %{
               status: :error,
               message: "command exited with status #{code}",
               stdout: output.stdout,
               stderr: output.stderr,
               exit_code: code
             }}

          {:signal, code, coredump} ->
            {:error,
             %{
               status: :error,
               message: "command killed by signal #{code}#{coredump_msg(coredump)}",
               exit_code: code,
               coredump: coredump,
               stdout: output.stdout,
               stderr: output.stderr
             }}
        end

      {:signal, signal, coredump} ->
        {:error,
         %{
           status: :error,
           message: "command killed by signal #{signal}#{coredump_msg(coredump)}",
           exit_code: signal,
           coredump: coredump,
           stdout: output.stdout,
           stderr: output.stderr
         }}
    end
  end

  defp send_task_error(%{task: task, owner_pid: owner_pid} = state, error) do
    DagLogger.unset()
    send(owner_pid, {:task_result, error, task.id, :error})
    {:stop, :normal, state}
  end

  defp append_output(nil, chunk), do: [chunk]
  defp append_output(output, chunk) when is_binary(output), do: [output, chunk]
  defp append_output(output, chunk) when is_list(output), do: output ++ [chunk]

  defp flatten(nil), do: ""
  defp flatten(output) when is_binary(output), do: output
  defp flatten(output) when is_list(output), do: IO.iodata_to_binary(output)

  defp coredump_msg(true), do: " (core dumped)"
  defp coredump_msg(false), do: ""
end
