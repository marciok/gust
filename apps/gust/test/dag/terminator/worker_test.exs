defmodule DAG.Terminator.WorkerTest do
  import Gust.FlowsFixtures
  use Gust.DataCase
  alias Gust.DAG.Terminator.Worker, as: Terminator

  setup do
    dag = dag_fixture(%{name: "test_dag"})
    run = run_fixture(%{dag_id: dag.id, claimed_by: to_string(Node.self())})
    task = task_fixture(%{run_id: run.id, name: "test_task"})

    start_link_supervised!(Terminator)

    %{task: task}
  end

  test "kill_task/2", %{task: task} do
    task_id = task.id

    {:ok, _} = Registry.register(Gust.Registry, "stage_run_#{task.run_id}", nil)

    parent = self()

    spawn(fn ->
      {:ok, _} = Registry.register(Gust.Registry, "task_#{task.id}", nil)
      send(parent, :registered)
      Process.sleep(3_000)
    end)

    receive do
      :registered -> :ok
    after
      100 -> flunk("Registry did not register in time")
    end

    [{task_pid, _val}] = Registry.lookup(Gust.Registry, "task_#{task.id}")
    ref = Process.monitor(task_pid)
    status = :cancelled

    Terminator.kill_task(task, status)

    assert_receive {:DOWN, ^ref, :process, ^task_pid, :killed}, 200

    assert_receive {:task_result, nil, ^task_id, ^status}, 200
  end

  test "cancel_timer/2", %{task: task} do
    task_id = task.id

    {:ok, _} = Registry.register(Gust.Registry, "stage_run_#{task.run_id}", nil)
    status = :cancelled

    Terminator.cancel_timer(task, status)

    assert_receive {:cancel_timer, ^task_id, ^status}, 200
  end
end
