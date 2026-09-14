defmodule GustShell.TaskWorker.Adapter do
  @moduledoc false

  use Gust.DAG.TaskWorker

  alias Gust.DAG.Logger, as: DagLogger

  @default_exec_opts [
    :stdin,
    :stdout,
    :stderr,
    :monitor,
    {:group, 0},
    :kill_group,
    {:kill_timeout, 5}
  ]

  @impl true
  def handle_info(:run, %{task: task, dag_def: dag_def, opts: opts} = state) do
    case resolve_command(task, dag_def, opts) do
      {:ok, {command, exec_opts}} ->
        DagLogger.set_task(task.id, task.attempt)

        case :exec.run(command, @default_exec_opts ++ exec_opts) do
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

  def handle_cast({:kill}, %{os_pid: os_pid} = state) do
    :exec.stop(os_pid)
    {:stop, :normal, state}
  end

  defp resolve_command(task, dag_def, opts) do
    raw_options = task_config(task, dag_def, opts)
    command = resolve_value(raw_options, ["run", :run, "command", :command])

    case command do
      nil -> {:error, RuntimeError.exception("shell task requires a command in task.params['run']")}
      value when is_binary(value) -> {:ok, {value, exec_options(raw_options)}}
      value -> {:ok, {to_string(value), exec_options(raw_options)}}
    end
  end

  defp task_config(task, dag_def, opts) do
    task_params = task.params || %{}
    dag_task_options = dag_def && (Map.get(dag_def.tasks || %{}, task.name) || %{})

    dag_task_options
    |> Map.merge(task_params)
    |> Map.merge(opts || %{})
  end

  defp resolve_value(source, keys) do
    Enum.find_value(keys, fn key ->
      case Map.get(source, key) do
        nil -> nil
        value -> value
      end
    end)
  end

  defp exec_options(raw_options) do
    raw_options
    |> Enum.reduce([], fn {key, value}, acc ->
      case normalize_exec_option(key, value) do
        nil -> acc
        option -> [option | acc]
      end
    end)
    |> Enum.reverse()
  end

  defp normalize_exec_option(key, value) do
    key = normalize_option_key(key)

    case key do
      :cd -> {:cd, value}
      :env -> {:env, normalize_env(value)}
      :stdin -> normalize_stdio(:stdin, value)
      :stdout -> normalize_stdio(:stdout, value)
      :stderr -> normalize_stdio(:stderr, value)
      :monitor -> if value in [true, "true"], do: :monitor, else: nil
      :kill_group -> if value in [true, "true"], do: :kill_group, else: nil
      :pty -> if value in [true, "true"], do: :pty, else: nil
      :pty_echo -> if value in [true, "true"], do: :pty_echo, else: nil
      :group -> {:group, value}
      :user -> {:user, value}
      :kill_timeout -> {:kill_timeout, value}
      :nice -> {:nice, value}
      :success_exit_code -> {:success_exit_code, value}
      :debug -> {:debug, value}
      :executable -> {:executable, value}
      :cgroup -> {:cgroup, value}
      _ -> nil
    end
  end

  defp normalize_option_key(key) do
    key
    |> to_string()
    |> String.trim()
    |> case do
      "cwd" -> :cd
      "working_dir" -> :cd
      "cd" -> :cd
      "env" -> :env
      "kill_timeout" -> :kill_timeout
      "group" -> :group
      "kill_group" -> :kill_group
      "monitor" -> :monitor
      "user" -> :user
      "nice" -> :nice
      "success_exit_code" -> :success_exit_code
      "pty" -> :pty
      "pty_echo" -> :pty_echo
      "stdin" -> :stdin
      "stdout" -> :stdout
      "stderr" -> :stderr
      "debug" -> :debug
      "executable" -> :executable
      "cgroup" -> :cgroup
      _ -> nil
    end
  end

  defp normalize_env(value) when is_map(value) do
    Enum.map(value, fn {k, v} -> {to_string(k), to_string(v)} end)
  end

  defp normalize_env(value) when is_list(value), do: value
  defp normalize_env(value), do: value

  defp normalize_stdio(key, true), do: key
  defp normalize_stdio(key, value) when is_binary(value), do: {key, value}
  defp normalize_stdio(_key, _value), do: nil

  defp finalize_task(%{stdout: stdout, stderr: stderr}, reason) do
    output = %{stdout: flatten(stdout), stderr: flatten(stderr)}

    case reason do
      :normal -> {:ok, Map.put(output, :exit_code, 0) |> Map.put(:status, :success)}
      {:exit_status, 0} -> {:ok, Map.put(output, :exit_code, 0) |> Map.put(:status, :success)}
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
