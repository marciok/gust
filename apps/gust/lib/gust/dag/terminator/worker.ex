defmodule Gust.DAG.Terminator.Worker do
  @moduledoc false
  @behaviour Gust.DAG.Terminator

  use GenServer

  alias Gust.Flows
  alias Gust.Registry, as: GustReg

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(init_arg) do
    {:ok, init_arg}
  end

  @impl true
  def handle_cast({:terminate, task, status, runtime}, state) do
    stage_pid = lookup("stage_run_#{task.run_id}")
    task_pid = lookup("task_#{task.id}")
    runtime.kill(task_pid)

    send(stage_pid, {:task_result, nil, task.id, status})

    {:noreply, state}
  end

  def handle_cast({:cancel_timer, task, status}, state) do
    stage_pid = lookup("stage_run_#{task.run_id}")
    send(stage_pid, {:cancel_timer, task.id, status})

    {:noreply, state}
  end

  @impl true
  def kill_task(task, status, runtime) do
    run = Flows.get_run!(task.run_id)
    run_node = String.to_atom(run.claimed_by)
    GenServer.cast({__MODULE__, run_node}, {:terminate, task, status, runtime})
  end

  @impl true
  def cancel_timer(task, status) do
    run = Flows.get_run!(task.run_id)
    run_node = String.to_atom(run.claimed_by)
    GenServer.cast({__MODULE__, run_node}, {:cancel_timer, task, status})
  end

  defp lookup(key) do
    [{pid, _val}] = Registry.lookup(GustReg, key)
    pid
  end
end
