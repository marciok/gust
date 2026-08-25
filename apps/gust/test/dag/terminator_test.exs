defmodule Gust.DAG.TerminatorTest do
  use Gust.DataCase, async: false

  import Gust.FlowsFixtures
  import Mox

  alias Gust.DAG.Terminator

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    replace_env(:dag_terminator, Gust.DAGTerminatorMock)

    dag = dag_fixture()
    run = run_fixture(%{dag_id: dag.id})
    task = task_fixture(%{run_id: run.id, name: "task", status: :running})

    %{run: run, task: task}
  end

  test "delegates task cancellation to the configured implementation", %{task: task} do
    Gust.DAGTerminatorMock
    |> expect(:cancel, fn ^task -> {:error, :delegated} end)

    assert {:error, :delegated} = Terminator.cancel(task)
    assert Terminator.impl() == Gust.DAGTerminatorMock
  end

  test "delegates run stops to the configured implementation", %{run: run} do
    Gust.DAGTerminatorMock
    |> expect(:stop_run, fn ^run -> {:error, :delegated} end)

    assert {:error, :delegated} = Terminator.stop_run(run)
  end
end
