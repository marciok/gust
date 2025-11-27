defmodule DAG.TaskRunnerSupervisor.DynamicSupervisorTest do
  use Gust.DataCase, async: true
  import Gust.FlowsFixtures
  alias Gust.DAG.Runner
  alias Gust.DAG.TaskRunnerSupervisor.DynamicSupervisor, as: TaskRunnerSupervisor

  test "start_child/3" do
    mod = MyPlainDag
    dag = dag_fixture()
    run = run_fixture(%{dag_id: dag.id})
    task = task_fixture(%{run_id: run.id, name: "green_day"})
    runner = Runner.Empty

    old = Application.get_env(:gust, :dag_task_runner)
    Application.put_env(:gust, :dag_task_runner, runner)
    on_exit(fn -> Application.put_env(:gust, :dag_task_runner, old) end)

    start_supervised!(TaskRunnerSupervisor)

    stage_pid = spawn(fn -> Process.sleep(100) end)

    {:ok, runner_pid} =
      TaskRunnerSupervisor.start_child(task, mod, stage_pid)

    assert Process.alive?(runner_pid)

    assert [{_id, ^runner_pid, :worker, [^runner]}] =
             DynamicSupervisor.which_children(TaskRunnerSupervisor)
  end
end
