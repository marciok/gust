defmodule Gust.DAG.TaskWaiterTest do
  use Gust.DataCase, async: false

  import Gust.FlowsFixtures
  import Mox

  alias Gust.DAG.TaskWaiter
  alias Gust.Flows
  alias Gust.PubSub

  setup :verify_on_exit!

  test "resume/2 with run_id resumes matching waiting tasks only on the requested run" do
    dag = dag_fixture()
    run = run_fixture(%{dag_id: dag.id, status: :waiting})
    other_run = run_fixture(%{dag_id: dag.id, status: :waiting})

    task =
      task_fixture(%{
        run_id: run.id,
        name: "await_payment",
        status: :waiting,
        waiting_for: "payment_received"
      })

    other_task =
      task_fixture(%{
        run_id: other_run.id,
        name: "await_payment",
        status: :waiting,
        waiting_for: "payment_received"
      })

    PubSub.subscribe_run(run.id)
    PubSub.subscribe_runs_pool()

    Gust.DAGRunTriggerMock
    |> expect(:dispatch_run, fn %Flows.Run{id: run_id} when run_id == run.id ->
      Gust.DAG.Run.Trigger.Requeue.dispatch_run(run)
    end)

    assert {:ok, [%Flows.Task{id: task_id}]} =
             TaskWaiter.resume(
               "payment_received",
               run_id: run.id,
               invoice_id: "inv_123"
             )

    assert task_id == task.id

    assert %Flows.Task{
             status: :created,
             result: %{},
             waiting_for: nil,
             wait_satisfied_at: %DateTime{},
             params: %{
               "__gust_wait_payload__" => %{"invoice_id" => "inv_123"}
             }
           } = Flows.get_task!(task.id)

    assert %Flows.Run{status: :enqueued} = Flows.get_run!(run.id)
    assert %Flows.Task{status: :waiting} = Flows.get_task!(other_task.id)
    assert %Flows.Run{status: :waiting} = Flows.get_run!(other_run.id)

    assert_receive {:dag, :run_status, %{run_id: run_id, task_id: ^task_id, status: :created}}
                   when run_id == run.id

    assert_receive {:dag, :run_status, %{run_id: run_id, status: :enqueued}}
                   when run_id == run.id

    assert_receive {:run_pool, :dispatch_run, %{run_id: run_id}} when run_id == run.id
  end

  test "resume/2 without run_id resumes all tasks waiting on the key" do
    dag = dag_fixture()
    first_run = run_fixture(%{dag_id: dag.id, status: :waiting})
    second_run = run_fixture(%{dag_id: dag.id, status: :waiting})
    other_run = run_fixture(%{dag_id: dag.id, status: :waiting})

    first_task =
      task_fixture(%{
        run_id: first_run.id,
        name: "await_payment",
        status: :waiting,
        waiting_for: "payment_received"
      })

    second_task =
      task_fixture(%{
        run_id: second_run.id,
        name: "await_payment",
        status: :waiting,
        waiting_for: "payment_received"
      })

    other_task =
      task_fixture(%{
        run_id: other_run.id,
        name: "await_payment",
        status: :waiting,
        waiting_for: "shipment_created"
      })

    Gust.DAGRunTriggerMock
    |> expect(:dispatch_run, 2, fn %Flows.Run{} = run ->
      Gust.DAG.Run.Trigger.Requeue.dispatch_run(run)
    end)

    assert {:ok, tasks} =
             TaskWaiter.resume(
               "payment_received",
               payload: %{"invoice_id" => "inv_123"}
             )

    assert Enum.map(tasks, & &1.id) |> Enum.sort() == Enum.sort([first_task.id, second_task.id])

    assert %Flows.Task{status: :created, waiting_for: nil, wait_satisfied_at: %DateTime{}} =
             Flows.get_task!(first_task.id)

    assert %Flows.Task{status: :created, waiting_for: nil, wait_satisfied_at: %DateTime{}} =
             Flows.get_task!(second_task.id)

    assert %Flows.Task{status: :waiting, waiting_for: "shipment_created", wait_satisfied_at: nil} =
             Flows.get_task!(other_task.id)

    assert %Flows.Run{status: :enqueued} = Flows.get_run!(first_run.id)
    assert %Flows.Run{status: :enqueued} = Flows.get_run!(second_run.id)
    assert %Flows.Run{status: :waiting} = Flows.get_run!(other_run.id)
  end

  test "clear_wait/1 clears persisted wait markers" do
    dag = dag_fixture()
    run = run_fixture(%{dag_id: dag.id})

    task =
      task_fixture(%{
        run_id: run.id,
        name: "await_payment",
        waiting_for: "payment_received",
        wait_satisfied_at: DateTime.utc_now()
      })

    assert %Flows.Task{waiting_for: nil, wait_satisfied_at: nil} =
             TaskWaiter.clear_wait(task)
  end
end
