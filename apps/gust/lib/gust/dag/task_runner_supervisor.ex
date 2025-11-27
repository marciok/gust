defmodule Gust.DAG.TaskRunnerSupervisor do
  @moduledoc false

  @callback start_child(Gust.Flows.Task.t(), module(), pid()) :: Supervisor.on_start_child()

  def start_child(task, mod, stage_pid), do: impl().start_child(task, mod, stage_pid)

  defp impl,
    do:
      Application.get_env(
        :gust,
        :dag_task_runner_supervisor,
        Gust.DAG.TaskRunnerSupervisor.DynamicSupervisor
      )
end
