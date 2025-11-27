defmodule Gust.DAG.RunnerSupervisor do
  @moduledoc false

  @callback start_child(Gust.Flows.Run.t(), Gust.DAG.Definition.t()) ::
              Supervisor.on_start_child()

  def start_child(run, dag_def),
    do: impl().start_child(run, dag_def)

  defp impl,
    do: Application.get_env(:gust, :dag_runner_supervisor)
end
