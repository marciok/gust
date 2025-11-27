defmodule Gust.DAG.StageRunnerSupervisor.DynamicSupervisor do
  @moduledoc false
  alias Gust.DAG.StageRunnerSupervisor
  @behaviour StageRunnerSupervisor

  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @impl true
  def start_child(dag_def, stage, run_id) do
    spec = {runner(), %{stage: stage, dag_def: dag_def, run_id: run_id}}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  def runner do
    Application.get_env(:gust, :dag_stage_runner)
  end
end
