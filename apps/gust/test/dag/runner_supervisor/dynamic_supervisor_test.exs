defmodule DAG.RunnerSupervisor.DynamicSupervisorTest do
  use Gust.DataCase, async: true
  import Gust.FlowsFixtures
  alias Gust.DAG.Runner
  alias Gust.DAG.RunnerSupervisor.DynamicSupervisor, as: RunnerSupervisor

  test "start_child/3" do
    mod = MyPlainDag

    dag_def = %Gust.DAG.Definition{
      mod: mod,
      stages: [["sublime"]]
    }

    dag = dag_fixture()
    run = run_fixture(%{dag_id: dag.id})
    runner = Runner.Empty

    old = Application.get_env(:gust, :dag_runner)
    Application.put_env(:gust, :dag_runner, runner)
    on_exit(fn -> Application.put_env(:gust, :dag_runner, old) end)

    start_supervised!(RunnerSupervisor)

    {:ok, runner_pid} =
      RunnerSupervisor.start_child(run, dag_def)

    assert Process.alive?(runner_pid)

    assert [{_id, ^runner_pid, :worker, [^runner]}] =
             DynamicSupervisor.which_children(RunnerSupervisor)
  end
end
