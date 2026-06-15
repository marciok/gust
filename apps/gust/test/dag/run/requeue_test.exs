defmodule DAG.Run.RequeueTest do
  alias Gust.Flows
  alias Gust.PubSub
  use Gust.DataCase, async: true

  import Gust.FlowsFixtures
  import Mox

  alias Gust.DAG.Run.Trigger.Requeue, as: Trigger

  setup :verify_on_exit!

  setup do
    dag = dag_fixture(%{name: "restart_me"})
    run = run_fixture(%{dag_id: dag.id})
    run_id = run.id
    %{run_id: run_id, run: run}
  end

  describe "reset_run/1" do
    test "update run to enqueued", %{run_id: run_id, run: run} do
      PubSub.subscribe_run(run_id)
      task = task_fixture(%{run_id: run_id, name: "my_task", status: :failed})
      run = Trigger.reset_run(run)

      assert %{status: :created} = Flows.get_task!(task.id)
      assert %{status: :enqueued} = Flows.get_run!(run.id)

      assert_receive {:dag, :run_status, %{run_id: ^run_id, status: :enqueued}}
    end
  end

  describe "reset_task/1" do
    test "update run to enqueued", %{run_id: run_id, run: run} do
      PubSub.subscribe_run(run_id)
      task = task_fixture(%{run_id: run.id, name: "wait", status: :failed})
      task_second = task_fixture(%{run_id: run.id, name: "bye", status: :failed})

      graph = %{
        "bye" => %{
          downstream: MapSet.new([]),
          upstream: MapSet.new(["for_me", "wait"])
        },
        "hi" => %{
          downstream: MapSet.new(["for_me", "wait"]),
          upstream: MapSet.new([])
        },
        "for_me" => %{
          downstream: MapSet.new(["bye"]),
          upstream: MapSet.new(["hi"])
        },
        "wait" => %{
          downstream: MapSet.new(["bye"]),
          upstream: MapSet.new(["hi"])
        }
      }

      [second_restarted, restarted_task] = Trigger.reset_task(graph, task)

      assert restarted_task.id == task.id
      assert restarted_task.status == :created
      assert second_restarted.id == task_second.id
      assert second_restarted.status == :created
      assert %Flows.Run{status: :enqueued} = Flows.get_run!(run_id)

      assert_receive {:dag, :run_status, %{run_id: ^run_id, status: :enqueued}}
    end

    test "collapses mapped task instances and resets the head task", %{run_id: run_id, run: run} do
      PubSub.subscribe_run(run_id)

      task =
        task_fixture(%{run_id: run.id, name: "mapped", status: :failed, map_index: 0})

      expanded_task =
        task_fixture(%{run_id: run.id, name: "mapped", status: :failed, map_index: 1})

      graph = %{
        "mapped" => %{downstream: MapSet.new([]), upstream: MapSet.new([])}
      }

      Gust.DAGTaskExpanderMock
      |> expect(:collapse_each, fn [^task, ^expanded_task] ->
        task
      end)

      assert [%Flows.Task{id: restarted_task_id, status: :created}] =
               Trigger.reset_task(graph, task)

      assert restarted_task_id == task.id
      assert %Flows.Task{status: :created} = Flows.get_task!(task.id)
      assert %Flows.Run{status: :enqueued} = Flows.get_run!(run_id)

      assert_receive {:dag, :run_status, %{run_id: ^run_id, status: :enqueued}}
    end

    test "resets a selected mapped task instance", %{run_id: run_id, run: run} do
      PubSub.subscribe_run(run_id)

      task =
        task_fixture(%{run_id: run.id, name: "mapped", status: :failed, map_index: 0})

      mapped_task =
        task_fixture(%{run_id: run.id, name: "mapped", status: :succeeded, map_index: 1})

      graph = %{
        "mapped" => %{downstream: MapSet.new([]), upstream: MapSet.new([])}
      }

      assert [%Flows.Task{id: restarted_task_id, status: :created, map_index: 1}] =
               Trigger.reset_task(graph, mapped_task, 1)

      assert restarted_task_id == mapped_task.id
      assert Flows.get_task!(task.id).status == :failed
      assert Flows.get_task!(mapped_task.id).status == :created
      assert %Flows.Run{status: :enqueued} = Flows.get_run!(run_id)

      assert_receive {:dag, :run_status, %{run_id: ^run_id, status: :enqueued}}
    end

    test "resets a selected mapped task and a normal downstream task", %{
      run_id: run_id,
      run: run
    } do
      first_mapped_task =
        task_fixture(%{run_id: run.id, name: "mapped", status: :failed, map_index: 0})

      selected_mapped_task =
        task_fixture(%{run_id: run.id, name: "mapped", status: :succeeded, map_index: 1})

      downstream_task =
        task_fixture(%{run_id: run.id, name: "normal", status: :succeeded})

      graph = %{
        "mapped" => %{
          downstream: MapSet.new(["normal"]),
          upstream: MapSet.new([])
        },
        "normal" => %{
          downstream: MapSet.new([]),
          upstream: MapSet.new(["mapped"])
        }
      }

      restarted_tasks = Trigger.reset_task(graph, selected_mapped_task, 1)

      assert MapSet.new(Enum.map(restarted_tasks, & &1.id)) ==
               MapSet.new([selected_mapped_task.id, downstream_task.id])

      assert Flows.get_task!(first_mapped_task.id).status == :failed
      assert Flows.get_task!(selected_mapped_task.id).status == :created
      assert Flows.get_task!(downstream_task.id).status == :created
      assert %Flows.Run{status: :enqueued} = Flows.get_run!(run_id)
    end
  end

  describe "dispatch_all_runs/1" do
    test "update all runs to enqueued from given dag.", %{run: run} do
      dag_id = run.dag_id
      _second_run = run_fixture(%{dag_id: dag_id})
      _already_enqueed_run = run_fixture(%{dag_id: dag_id, status: :enqueued})

      assert [%Flows.Run{status: :enqueued}, %Flows.Run{status: :enqueued}] =
               Trigger.dispatch_all_runs(dag_id)
    end
  end

  describe "dispatch_run/1" do
    test "dag is disabled it does not enqueue", %{run_id: run_id, run: run} do
      dag = Flows.get_dag!(run.dag_id)
      Flows.toggle_enabled(dag)

      PubSub.subscribe_run(run_id)
      PubSub.subscribe_runs_pool()

      run = Trigger.dispatch_run(run)

      assert %{status: :created} = run

      refute_receive {:run_pool, :dispatch_run, %{run_id: ^run_id}}
    end

    test "update run to enqueued and notify pooler", %{run_id: run_id, run: run} do
      PubSub.subscribe_run(run_id)
      PubSub.subscribe_runs_pool()

      run = Trigger.dispatch_run(run)

      assert %{status: :enqueued} = run

      assert_receive {:dag, :run_status, %{run_id: ^run_id, status: :enqueued}}
      assert_receive {:run_pool, :dispatch_run, %{run_id: ^run_id}}
    end
  end
end
