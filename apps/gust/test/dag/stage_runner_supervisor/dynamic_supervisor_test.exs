defmodule DAG.StageRunnerSupervisor.DynamicSupervisorTest do
  use Gust.DataCase, async: true
  alias Gust.DAG.Runner
  alias Gust.DAG.StageRunnerSupervisor.DynamicSupervisor, as: StageRunnerSupervisor

  test "start_child/3" do
    mod = MyPlainDag

    dag_def = %Gust.DAG.Definition{
      mod: mod,
      stages: [["sublime"]]
    }

    runner = Runner.Empty
    old = Application.get_env(:gust, :dag_stage_runner)
    Application.put_env(:gust, :dag_stage_runner, runner)

    on_exit(fn -> Application.put_env(:gust, :dag_stage_runner, old) end)

    start_supervised!(StageRunnerSupervisor)
    task_id = "123"
    run_id = "321"

    {:ok, runner_pid} =
      StageRunnerSupervisor.start_child(dag_def, [task_id], run_id)

    assert Process.alive?(runner_pid)

    assert [{_id, ^runner_pid, :worker, [^runner]}] =
             DynamicSupervisor.which_children(StageRunnerSupervisor)
  end
end
