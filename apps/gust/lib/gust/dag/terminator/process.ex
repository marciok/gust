defmodule Gust.DAG.Terminator.Process do
  @moduledoc false
  @behaviour Gust.DAG.Terminator

  alias Gust.Registry, as: GustReg

  def kill_task(task, status) do
    stage_pid = lookup("stage_run_#{task.run_id}")
    task_pid = lookup("task_#{task.id}")

    true = Process.exit(task_pid, :kill)

    send(stage_pid, {:task_result, nil, task.id, status})
  end

  def cancel_timer(task, status) do
    stage_pid = lookup("stage_run_#{task.run_id}")
    send(stage_pid, {:cancel_timer, task.id, status})
  end

  defp lookup(key) do
    [{pid, _val}] = Registry.lookup(GustReg, key)
    pid
  end
end
