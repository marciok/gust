defmodule Gust.DAG.Terminator.GatewayTest do
  use Gust.DataCase, async: false

  import Gust.FlowsFixtures
  import Mox

  alias Gust.DAG.Terminator.Gateway
  alias Gust.Flows

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    replace_env(:dag_run_gateway, Gust.RunGatewayMock)

    dag = dag_fixture()
    run = run_fixture(%{dag_id: dag.id})
    task = task_fixture(%{run_id: run.id, name: "task", status: :running})

    %{run: run, task: task}
  end

  test "routes active task cancellation through the run gateway", %{run: run, task: task} do
    Gust.RunGatewayMock
    |> expect(:call, fn routed_run, {:cancel_task, task_id} ->
      assert routed_run.id == run.id
      assert task_id == task.id
      {:ok, task}
    end)

    assert {:ok, ^task} = Gateway.cancel(task)
  end

  test "fails a waiting task directly when its run is inactive", %{run: run, task: task} do
    {:ok, _run} = Flows.update_run_status(run, :waiting)
    {:ok, task} = Flows.update_task_status(task, :waiting)

    expect(Gust.RunGatewayMock, :call, fn routed_run, {:cancel_task, task_id} ->
      assert routed_run.id == run.id
      assert task_id == task.id
      {:error, :run_not_active}
    end)

    Gust.DAGRunTriggerMock
    |> expect(:dispatch_run, fn dispatched_run ->
      assert dispatched_run.id == run.id
      dispatched_run
    end)

    assert {:ok, %Flows.Task{id: task_id, status: :failed}} = Gateway.cancel(task)
    assert task_id == task.id
  end

  test "does not rewrite an inactive non-waiting task", %{run: run, task: task} do
    expect(Gust.RunGatewayMock, :call, fn routed_run, {:cancel_task, task_id} ->
      assert routed_run.id == run.id
      assert task_id == task.id
      {:error, :run_not_active}
    end)

    assert {:error, :run_not_active} = Gateway.cancel(task)
    assert Flows.get_task!(task.id).status == :running
  end
end
