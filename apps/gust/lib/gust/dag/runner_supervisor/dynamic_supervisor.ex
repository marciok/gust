defmodule Gust.DAG.RunnerSupervisor.DynamicSupervisor do
  @moduledoc false
  use DynamicSupervisor
  @behaviour Gust.DAG.RunnerSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @impl true
  def start_child(run, dag_def) do
    spec = {runner(), %{run: run, dag_def: dag_def}}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  def runner do
    Application.get_env(:gust, :dag_runner, Gust.DAG.Runner.DAGWorker)
  end
end
