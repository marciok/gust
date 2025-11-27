defmodule Gust.DAG.StageRunnerSupervisor do
  @moduledoc false

  @callback start_child(Gust.DAG.Definition.t(), [term()], term()) ::
              Supervisor.on_start_child()

  def start_child(dag_def, stage, run_id),
    do: impl().start_child(dag_def, stage, run_id)

  defp impl,
    do: Application.get_env(:gust, :dag_stage_runner_supervisor)
end
