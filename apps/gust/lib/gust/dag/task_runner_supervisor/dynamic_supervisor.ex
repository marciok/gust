defmodule Gust.DAG.TaskRunnerSupervisor.DynamicSupervisor do
  @moduledoc false

  @behaviour Gust.DAG.TaskRunnerSupervisor
  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @impl true
  def start_child(task, mod, stage_pid) do
    spec = {runner(), %{task: task, mod: mod, stage_pid: stage_pid}}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  def runner do
    Application.get_env(:gust, :dag_task_runner, Gust.DAG.Runner.TaskWorker)
  end
end
