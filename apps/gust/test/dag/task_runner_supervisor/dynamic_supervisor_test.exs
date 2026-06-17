defmodule DAG.TaskRunnerSupervisor.DynamicSupervisorTest do
  use Gust.DataCase, async: false
  import Gust.FlowsFixtures
  alias Gust.DAG.TaskRunnerSupervisor.DynamicSupervisor, as: TaskRunnerSupervisor
  import Mox

  setup :set_mox_from_context

  test "start_child/4" do
    dag = dag_fixture()
    run = run_fixture(%{dag_id: dag.id})
    task_name = "green_day"
    task = task_fixture(%{run_id: run.id, name: task_name})

    dag_content = """
    defmodule DagToBeRun do
      def #{task_name}(args) do
        args
      end
    end
    """

    [{mod, _bin}] = Code.compile_string(dag_content)

    Gust.DAGLoggerMock
    |> expect(:set_task, fn _task_name, _attempt -> nil end)
    |> expect(:unset, fn -> nil end)

    on_exit(fn ->
      :code.purge(mod)
      :code.delete(mod)
    end)

    dag_def = %Gust.DAG.Definition{adapter: :elixir}

    start_supervised!(TaskRunnerSupervisor)

    stage_pid = spawn(fn -> Process.sleep(100) end)

    {:ok, runner_pid} =
      TaskRunnerSupervisor.start_child(task, dag_def, stage_pid, %{})

    Process.monitor(runner_pid)

    assert Process.alive?(runner_pid)

    assert [{_id, ^runner_pid, :worker, [Gust.DAG.TaskWorker.Adapters.Elixir]}] =
             DynamicSupervisor.which_children(TaskRunnerSupervisor)

    assert_receive {:DOWN, _ref, :process, _task_pid, :normal}
  end
end
