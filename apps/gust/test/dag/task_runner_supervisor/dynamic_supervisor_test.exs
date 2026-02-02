defmodule DAG.TaskRunnerSupervisor.DynamicSupervisorTest do
  use Gust.DataCase, async: true
  import Gust.FlowsFixtures
  alias Gust.DAG.TaskRunnerSupervisor.DynamicSupervisor, as: TaskRunnerSupervisor

  test "start_child/4" do
    dag = dag_fixture()
    run = run_fixture(%{dag_id: dag.id})
    task = task_fixture(%{run_id: run.id, name: "green_day"})

    dag_def = %Gust.DAG.Definition{adapter: :elixir}

    start_supervised!(TaskRunnerSupervisor)

    stage_pid = spawn(fn -> Process.sleep(100) end)

    {:ok, runner_pid} =
      TaskRunnerSupervisor.start_child(task, dag_def, stage_pid, %{})

    assert Process.alive?(runner_pid)

    assert [{_id, ^runner_pid, :worker, [Gust.DAG.TaskWorker.Adapters.Elixir]}] =
             DynamicSupervisor.which_children(TaskRunnerSupervisor)
  end
end
