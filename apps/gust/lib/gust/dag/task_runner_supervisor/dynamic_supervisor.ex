defmodule Gust.DAG.TaskRunnerSupervisor.DynamicSupervisor do
  @moduledoc false
  alias Gust.DAG.Adapter

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
  def start_child(task, dag_def, stage_pid, opts) do
    spec =
      {worker(dag_def.adapter), %{task: task, dag_def: dag_def, stage_pid: stage_pid, opts: opts}}

    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  def worker(adapter) do
    Adapter.impl!(adapter, :task_worker)
  end
end
