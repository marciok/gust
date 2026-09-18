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
    :kill_group
  ]

  @impl true
  def handle_info(:run, %{task: task, dag_def: dag_def, opts: opts} = state) do
    case resolve_command(task, dag_def, opts) do
      {:ok, {command, exec_opts}} ->
        DagLogger.set_task(task.id, task.attempt)
        found_opts = Enum.reduce(exec_opts, MapSet.new(), fn
          ({opt, _}, acc) when opt in [:group, :stdin, :stdout, :stderr] -> MapSet.put(acc, opt)
          (_, acc) -> acc
        end)
        add_opts = Enum.filter(@default_exec_opts, fn
          ({opt, _}) -> not MapSet.member?(found_opts, opt)
          (opt) -> not MapSet.member?(found_opts, opt)
        end)
        case :exec.run(command, add_opts ++ exec_opts) do
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

  def handle_info({:stdout, _other_pid, _data}, state) do
    # Ignore stdout from mismatched PIDs
    {:noreply, state}
  end

  def handle_info({:stderr, os_pid, data}, %{os_pid: os_pid} = state) do
    {:noreply, %{state | stderr: append_output(state.stderr, data)}}
  end

  def handle_info({:stderr, _other_pid, _data}, state) do
    # Ignore stderr from mismatched PIDs
    {:noreply, state}
  end

  def handle_info({:DOWN, os_pid, :process, _pid, reason}, %{os_pid: os_pid} = state) do
    {status, result} = finalize_task(state, reason)

    DagLogger.unset()
    send(state.owner_pid, {:task_result, result, state.task.id, status})

    {:stop, :normal, state}
  end

  def handle_info({:DOWN, _other_pid, :process, _pid, _reason}, state) do
    # Ignore DOWN messages from mismatched PIDs
    {:noreply, state}
  end

  def handle_cast({:kill}, %{os_pid: os_pid} = state) do
    :exec.stop(os_pid)
    {:stop, :normal, state}
  end

  def resolve_command(task, dag_def, opts) do
    raw_options = task_config(task, dag_def, opts)
    command = resolve_value(raw_options, ["run", :run, "command", :command])

    case command do
      nil -> {:error, RuntimeError.exception("shell task requires a command in task.params['run']")}
      value when is_binary(value) -> {:ok, {value, normalize_options(raw_options)}}
      value -> {:ok, {to_string(value), normalize_options(raw_options)}}
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
    Enum.find_value(keys, fn key -> Map.get(source, key) end)
  end

  def normalize_options(raw_options) do
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
    key |> normalize_option_key() |> normalize_exec_option2(value)
  end

  defp normalize_exec_option2(:cd, value), do: {:cd, value}
  defp normalize_exec_option2(:cgroup, value), do: {:cgroup, value}
  defp normalize_exec_option2(:debug, value), do: {:debug, value}
  defp normalize_exec_option2(:env, value), do: {:env, normalize_env(value)}
  defp normalize_exec_option2(:executable, value), do: {:executable, value}
  defp normalize_exec_option2(:group, value), do: {:group, value}
  defp normalize_exec_option2(:kill_timeout, value), do: {:kill_timeout, value}
  defp normalize_exec_option2(:nice, value), do: {:nice, value}
  defp normalize_exec_option2(:pty, value), do: (if value in [true, "true"], do: :pty, else: nil)
  defp normalize_exec_option2(:pty_echo, value), do: (if value in [true, "true"], do: :pty_echo, else: nil)
  defp normalize_exec_option2(:stderr, value), do: normalize_stdio(:stderr, value)
  defp normalize_exec_option2(:stdin, value), do: normalize_stdio(:stdin, value)
  defp normalize_exec_option2(:stdout, value), do: normalize_stdio(:stdout, value)
  defp normalize_exec_option2(:success_exit_code, value), do: {:success_exit_code, value}
  defp normalize_exec_option2(:user, value), do: {:user, value}
  defp normalize_exec_option2(_, _value), do: nil

  defp normalize_option_key(key) do
    key
    |> to_string()
    |> String.trim()
    |> normalize_option_key2()
  end

  @options_map %{
    "cd" => :cd,
    "cgroup" => :cgroup,
    "cwd" => :cd,
    "debug" => :debug,
    "env" => :env,
    "executable" => :executable,
    "group" => :group,
    "kill_timeout" => :kill_timeout,
    "nice" => :nice,
    "pty_echo" => :pty_echo,
    "pty" => :pty,
    "stderr" => :stderr,
    "stdin" => :stdin,
    "stdout" => :stdout,
    "success_exit_code" => :success_exit_code,
    "user" => :user,
    "working_dir" => :cd,
  }
  defp normalize_option_key2(key), do: Map.get(@options_map, key, nil)

  defp normalize_env(value) when is_map(value) do
    Enum.map(value, fn {k, v} -> {to_string(k), to_string(v)} end)
  end

  defp normalize_env(value) when is_list(value), do: value
  defp normalize_env(value), do: value

  defp normalize_stdio(key, "null"), do: {key, :null}
  defp normalize_stdio(key, "close"), do: {key, :close}
  defp normalize_stdio(key, value) when is_binary(value), do: {key, value}
  defp normalize_stdio(_key, _value), do: nil

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
