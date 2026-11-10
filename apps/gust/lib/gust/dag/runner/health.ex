defmodule Gust.DAG.Runner.Health do
  @moduledoc """
  Read-only health check for running tasks.

  Compares the status stored in the database with the Elixir processes that
  should be backing a run (`DAGWorker`) and its tasks (`TaskWorker`) on the
  node that owns the run. The lookup runs on the owning node through `:erpc`,
  and only plain, serializable data comes back.

  It never calls into the workers themselves, since a `TaskWorker` running an
  Elixir task is busy inside its callback and cannot answer messages.

  Each task gets a verdict:

    * `:healthy` - the database says `running` and the process is alive
    * `:zombie` - the database says `running` and no process exists on the owner node
    * `:unknown` - the owner node is unreachable or the lookup failed
    * `:not_running` - the database does not say `running`
  """

  alias Gust.DAG.Runner.RunOwner
  alias Gust.DAG.TaskWorker
  alias Gust.Flows
  alias Gust.Flows.{Run, Task}

  @process_info_keys [:status, :current_function, :message_queue_len, :memory, :reductions]

  @type verdict :: :healthy | :zombie | :unknown | :not_running

  @doc "Checks a single task."
  def inspect_task(%Task{} = task), do: inspect_tasks([task])

  @doc """
  Checks a list of tasks from the same run, such as the map indexes of a
  mapped task. Returns one entry per task.
  """
  def inspect_tasks([%Task{run_id: run_id} | _rest] = tasks) do
    run = Flows.get_run!(run_id)
    tasks = Enum.map(tasks, &(Flows.get_task(&1.id) || &1))

    inspect_run_tasks(run, tasks)
  end

  @doc """
  Checks a run: its `DAGWorker` and every task the database marks as `running`.
  """
  def inspect_run(%Run{id: run_id}) do
    %Run{tasks: tasks} = run = Flows.get_run_with_tasks!(run_id, :omit_payloads)

    running =
      tasks
      |> Enum.filter(&(&1.status == :running))
      |> Enum.sort_by(&{&1.name, &1.map_index || -1})

    inspect_run_tasks(run, running)
  end

  defp inspect_run_tasks(%Run{} = run, tasks) do
    keys = Enum.map(tasks, &TaskWorker.registry_name/1)

    {owner, snapshot} =
      case RunOwner.node(run) do
        {:ok, owner} -> {owner, fetch_snapshot(owner, run.id, keys)}
        {:error, reason} -> {nil, {:error, reason}}
      end

    build_report(run, tasks, owner, snapshot)
  end

  @doc """
  Collects the process snapshot of a run's `DAGWorker` and the given task
  registry keys on the local node. `inspect_task/1` and friends call it through
  `:erpc` on the node that owns the run.
  """
  def local_snapshot(run_id, task_keys) do
    %{
      node: to_string(node()),
      dag_worker: lookup("dag_run_#{run_id}"),
      tasks: Map.new(task_keys, &{&1, lookup(&1)})
    }
  end

  defp fetch_snapshot(owner, run_id, keys) when owner == node() do
    {:ok, local_snapshot(run_id, keys)}
  end

  defp fetch_snapshot(owner, run_id, keys) do
    {:ok, :erpc.call(owner, __MODULE__, :local_snapshot, [run_id, keys], timeout())}
  catch
    :error, {:erpc, :timeout} -> {:error, :timeout}
    _kind, _reason -> {:error, :lookup_failed}
  end

  defp build_report(%Run{} = run, tasks, owner, snapshot) do
    {error, remote} =
      case snapshot do
        {:ok, remote} -> {nil, remote}
        {:error, reason} -> {reason, nil}
      end

    %{
      checked_at: DateTime.utc_now(),
      error: error,
      run: %{
        id: run.id,
        status: run.status,
        claimed_by: run.claimed_by,
        claim_expires_at: run.claim_expires_at,
        owner_node: owner && to_string(owner),
        node_connected: not is_nil(owner),
        dag_worker: remote && remote.dag_worker
      },
      tasks: Enum.map(tasks, &task_report(&1, remote))
    }
  end

  defp task_report(%Task{} = task, remote) do
    key = TaskWorker.registry_name(task)
    process = remote && Map.get(remote.tasks, key)

    %{
      id: task.id,
      name: task.name,
      map_index: task.map_index,
      status: task.status,
      registry_key: key,
      process: process,
      verdict: verdict(task.status, remote, process)
    }
  end

  defp verdict(status, _remote, _process) when status != :running, do: :not_running
  defp verdict(_status, nil, _process), do: :unknown
  defp verdict(_status, _remote, %{alive: true}), do: :healthy
  defp verdict(_status, _remote, _process), do: :zombie

  defp lookup(key) do
    case Registry.lookup(Gust.Registry, key) do
      [{pid, value}] -> process_report(pid, value)
      [] -> nil
    end
  end

  defp process_report(pid, value) do
    info = Process.info(pid, @process_info_keys)

    %{
      pid: inspect(pid),
      alive: not is_nil(info),
      info: info && Map.new(info, &format_info/1),
      os_process: os_process(value)
    }
  end

  defp format_info({:current_function, {mod, fun, arity}}),
    do: {:current_function, "#{inspect(mod)}.#{fun}/#{arity}"}

  defp format_info({key, value}), do: {key, value}

  defp os_process(%{os_pid: os_pid}) when is_integer(os_pid) do
    %{os_pid: os_pid, alive: os_alive?(os_pid)}
  end

  defp os_process(_value), do: nil

  defp os_alive?(os_pid) do
    case System.cmd(
           "/bin/sh",
           ["-c", ~s(kill -0 "$1"), "health-check", Integer.to_string(os_pid)],
           stderr_to_stdout: true
         ) do
      {_output, 0} -> true
      {_output, _status} -> false
    end
  end

  defp timeout, do: Application.get_env(:gust, :health_check_timeout, 2_000)
end
