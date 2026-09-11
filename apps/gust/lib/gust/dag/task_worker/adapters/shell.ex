defmodule Gust.DAG.TaskWorker.Adapters.Shell do
  @moduledoc false

  use Gust.DAG.TaskWorker

  alias Gust.DAG.Logger, as: DagLogger

  @impl true
  def handle_info(:run, %{task: task, dag_def: dag_def} = state) do
    command = resolve_command(task, dag_def)

    DagLogger.set_task(task.id, task.attempt)

    os_pid =
      :exec.run(command, [
        :stdin,
        :stdout,
        :stderr,
        :monitor,
        {:group, 0},
        :kill_group,
        {:kill_timeout, 5}
      ])
      |> case do
        {:ok, _exec_pid, pid} -> pid
        {:error, reason} -> raise("failed to start shell task: #{inspect(reason)}")
      end

    {:noreply, %{state | os_pid: os_pid, stdout: [], stderr: []}}
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
    case Map.get(task.params, "command") || Map.get(task.params, :command) do
      nil ->
        if dag_def && Map.get(dag_def, :command) do
          dag_def.command
        else
          raise("shell task requires a command in task.params['command']")
        end

      command when is_binary(command) ->
        command

      command ->
        to_string(command)
    end
  end

  defp finalize_task(%{stdout: stdout, stderr: stderr}, reason) do
    case reason do
      :normal ->
        {:ok, %{status: :success, stdout: flatten(stdout), stderr: flatten(stderr), exit_code: 0}}

      {:exit_status, code} ->
        case :exec.status(code) do
          {:status, code} ->
            {:error,
             %{
               status: :error,
               message: "command exited with status #{code}",
               stdout: flatten(stdout),
               stderr: flatten(stderr),
               exit_code: code
             }}

          {:signal, code, coredump} ->
            {:error,
             %{
               status: :error,
               message: "command killed by signal #{code}#{coredump_msg(coredump)}",
               exit_code: code,
               coredump: coredump,
               stdout: flatten(stdout),
               stderr: flatten(stderr)
             }}
        end

      {:signal, signal, coredump} ->
        {:error,
         %{
           status: :error,
           message: "command killed by signal #{signal}#{coredump_msg(coredump)}",
           exit_code: signal,
           coredump: coredump,
           stdout: flatten(stdout),
           stderr: flatten(stderr)
         }}
    end
  end

  defp append_output(output, chunk) when is_binary(output), do: [output, chunk]
  defp append_output(output, chunk) when is_list(output), do: output ++ [chunk]
  defp append_output(_output, chunk), do: [chunk]

  defp flatten(output) when is_binary(output), do: output
  defp flatten(output) when is_list(output), do: output |> Enum.reverse() |> IO.iodata_to_binary()

  defp coredump_msg(true), do: " (core dumped)"
  defp coredump_msg(false), do: ""
end
