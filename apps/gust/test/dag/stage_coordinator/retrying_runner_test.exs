defmodule DAG.StageCoordinator.RetryingRunnerTest do
  use Gust.DataCase, async: false

  alias Gust.Flows
  import Gust.FlowsFixtures
  alias Gust.DAG.StageCoordinator.RetryingRunner
  import Mox

  setup :verify_on_exit!

  setup do
    dag = dag_fixture()
    run = run_fixture(%{dag_id: dag.id})
    task = task_fixture(%{run_id: run.id, name: "hi"})
    %{run: run, task: task}
  end

  def create_upstreams(%{task: task, run: run}) do
    upstream_task1 = task_fixture(%{run_id: run.id, name: "john_mayer"})
    upstream_task2 = task_fixture(%{run_id: run.id, name: "jack_johnson"})
    tasks = %{task.name => %{upstream: [upstream_task1.name, upstream_task2.name]}}
    %{upstream_task1: upstream_task1, upstream_task2: upstream_task2, tasks: tasks}
  end

  describe "new/1" do
    test "fill struct with pending runs" do
      pending_task_ids = [1, 2, 3]
      coord = RetryingRunner.new(pending_task_ids)
      assert coord.running == MapSet.new(pending_task_ids)
    end
  end

  describe "process_task/2 when upstream is not present" do
    test "upstream does not exsists", %{task: task} do
      tasks = %{task.name => %{upstream: []}}
      assert RetryingRunner.process_task(task, tasks) == :ok
    end
  end

  describe "process_task/2 when task staus is not :running" do
    test "already_processed return for failed status", %{task: task} do
      {:ok, task} = Flows.update_task_status(task, :failed)
      tasks = %{task.name => %{upstream: []}}
      assert RetryingRunner.process_task(task, tasks) == :already_processed
    end

    test "already_processed return for succeeded status", %{task: task} do
      {:ok, task} = Flows.update_task_status(task, :succeeded)
      tasks = %{task.name => %{upstream: []}}
      assert RetryingRunner.process_task(task, tasks) == :already_processed
    end

    test "already_processed return for upstream_failed status", %{task: task} do
      {:ok, task} = Flows.update_task_status(task, :upstream_failed)
      tasks = %{task.name => %{upstream: []}}
      assert RetryingRunner.process_task(task, tasks) == :already_processed
    end

    test "already_processed return for retrying status", %{task: task} do
      {:ok, task} = Flows.update_task_status(task, :retrying)
      tasks = %{task.name => %{upstream: []}}
      assert RetryingRunner.process_task(task, tasks) == :ok
    end
  end

  describe "process_task/2 when upstream is present" do
    setup [:create_upstreams]

    test "no upstream failed", %{
      task: task,
      upstream_task1: upstream_task1,
      upstream_task2: upstream_task2,
      tasks: tasks
    } do
      Flows.update_task_status(upstream_task1, :succeeded)
      Flows.update_task_status(upstream_task2, :succeeded)

      assert RetryingRunner.process_task(task, tasks) == :ok
    end

    test "one upstream errored as failed", %{
      task: task,
      upstream_task1: upstream_task1,
      upstream_task2: upstream_task2,
      tasks: tasks
    } do
      Flows.update_task_status(upstream_task1, :succeeded)
      Flows.update_task_status(upstream_task2, :failed)

      assert RetryingRunner.process_task(task, tasks) == :upstream_failed
    end

    test "one upstream erroes as upstream_failed", %{
      task: task,
      upstream_task1: upstream_task1,
      upstream_task2: upstream_task2,
      tasks: tasks
    } do
      Flows.update_task_status(upstream_task1, :succeeded)
      Flows.update_task_status(upstream_task2, :upstream_failed)

      assert RetryingRunner.process_task(task, tasks) == :upstream_failed
    end
  end

  describe "put_running/2" do
    test "adds task_ids to running and marks them :running", %{run: run, task: task} do
      sec_task = task_fixture(%{run_id: run.id, name: "second_task"})
      sec_task_id = sec_task.id

      coord0 = %{
        running: MapSet.new([sec_task.id]),
        retrying: %{sec_task.id => 2}
      }

      new_running = MapSet.new([sec_task.id, task.id])

      assert %{
               running: ^new_running,
               retrying: %{^sec_task_id => 2}
             } =
               RetryingRunner.put_running(coord0, task.id)
    end
  end

  describe "update_restart_timer/3" do
    test "adds restart_timer ref to the retrying task", %{task: task} do
      ref = make_ref()
      task_id = task.id
      coord0 = %{retrying: %{task.id => %{attempts: 2}}}

      assert %{retrying: %{^task_id => %{restart_timer: ^ref, attempts: 2}}} =
               RetryingRunner.update_restart_timer(coord0, task, ref)
    end
  end

  describe "apply_task_result/3 for non-normal reason" do
    test "max retry has been reached without other retrying tasks", %{task: task} do
      coord = %RetryingRunner{
        running: MapSet.new([task.id]),
        retrying: %{task.id => %{attempt: 3}}
      }

      result = RetryingRunner.apply_task_result(coord, task, :error)

      assert {:finished, %RetryingRunner{running: %MapSet{}, retrying: %{}}} =
               result
    end

    test "max retry has been reached with other retrying tasks", %{run: run, task: task} do
      sec_task = task_fixture(%{run_id: run.id, name: "second_task"})
      sec_task_id = sec_task.id

      coord = %RetryingRunner{
        running: MapSet.new([task.id]),
        retrying: %{task.id => %{attempt: 3}, sec_task_id => %{attempt: 2}}
      }

      result = RetryingRunner.apply_task_result(coord, task, :error)

      assert {:continue,
              %RetryingRunner{running: %MapSet{}, retrying: %{^sec_task_id => %{attempt: 2}}}} =
               result
    end

    test "max retry has not been reached", %{run: run, task: task} do
      task_id = task.id
      Gust.PubSub.subscribe_run(run.id)
      sec_task = task_fixture(%{run_id: run.id, name: "second_task"})
      sec_task_id = sec_task.id

      coord = %RetryingRunner{
        running: MapSet.new([task.id]),
        retrying: %{sec_task.id => %{attempt: 2}}
      }

      delay = 1818
      attempt = task.attempt

      Gust.DAGTaskDelayerMock |> expect(:calc_delay, fn ^attempt -> delay end)

      result = RetryingRunner.apply_task_result(coord, task, :error)
      updated_task = Flows.get_task!(task.id)

      assert {:reschedule,
              %RetryingRunner{
                running: %MapSet{},
                retrying: %{^task_id => %{attempt: 1}, ^sec_task_id => %{attempt: 2}}
              }, ^updated_task, ^delay} = result
    end

    test "task retrying one more time increments counter", %{run: run, task: task} do
      task_id = task.id
      Gust.PubSub.subscribe_run(run.id)
      sec_task = task_fixture(%{run_id: run.id, name: "second_task"})
      sec_task_id = sec_task.id

      coord = %RetryingRunner{
        running: MapSet.new([task.id]),
        retrying: %{task.id => %{attempt: 1}, sec_task_id => %{attempt: 2}}
      }

      delay = 1818
      attempt = task.attempt
      Gust.DAGTaskDelayerMock |> expect(:calc_delay, fn ^attempt -> delay end)

      result = RetryingRunner.apply_task_result(coord, task, :error)
      updated_task = Flows.get_task!(task.id)

      assert {:reschedule,
              %RetryingRunner{
                running: %MapSet{},
                retrying: %{^task_id => %{attempt: 2}, ^sec_task_id => %{attempt: 2}}
              }, ^updated_task, ^delay} = result
    end
  end

  describe "apply_task_result/3 when already processed" do
    test "continue if tasks area running", %{task: task} do
      coord = %RetryingRunner{running: MapSet.new([task.id]), retrying: %{}}

      assert {:finished, %RetryingRunner{running: %MapSet{}, retrying: %{}}} ==
               RetryingRunner.apply_task_result(coord, task, :already_processed)
    end

    test "tasks are left in running", %{run: run, task: task} do
      sec_task = task_fixture(%{run_id: run.id, name: "second_task"})

      coord = %RetryingRunner{
        running: MapSet.new([task.id, sec_task.id]),
        retrying: %{}
      }

      remaining = MapSet.new([sec_task.id])

      assert {:continue, %RetryingRunner{running: ^remaining, retrying: %{}}} =
               RetryingRunner.apply_task_result(coord, task, :already_processed)
    end
  end

  describe "apply_task_result/3 when cancelled" do
    test "continue if tasks area running", %{task: task} do
      coord = %RetryingRunner{running: MapSet.new([task.id]), retrying: %{}}

      assert {:finished, %RetryingRunner{running: %MapSet{}, retrying: %{}}} ==
               RetryingRunner.apply_task_result(coord, task, :cancelled)
    end
  end

  describe "apply_task_result/3 when upstream failed" do
    test "continue if tasks area running", %{task: task} do
      coord = %RetryingRunner{running: MapSet.new([task.id]), retrying: %{}}

      assert {:finished, %RetryingRunner{running: %MapSet{}, retrying: %{}}} ==
               RetryingRunner.apply_task_result(coord, task, :upstream_failed)
    end

    test "tasks are left in running", %{run: run, task: task} do
      sec_task = task_fixture(%{run_id: run.id, name: "second_task"})

      coord = %RetryingRunner{
        running: MapSet.new([task.id, sec_task.id]),
        retrying: %{}
      }

      remaining = MapSet.new([sec_task.id])

      assert {:continue, %RetryingRunner{running: ^remaining, retrying: %{}}} =
               RetryingRunner.apply_task_result(coord, task, :ok)
    end
  end

  describe "apply_task_result/3 for normal reason" do
    test "no tasks left in running and retrying was sucessful", %{task: task} do
      coord = %RetryingRunner{running: MapSet.new([task.id]), retrying: %{task.id => 1}}

      assert RetryingRunner.apply_task_result(coord, task, :ok) ==
               {:finished, %RetryingRunner{running: %MapSet{}, retrying: %{}}}
    end

    test "no tasks left in running", %{task: task} do
      coord = %RetryingRunner{running: MapSet.new([task.id]), retrying: %{}}

      assert {:finished, %RetryingRunner{running: %MapSet{}, retrying: %{}}} ==
               RetryingRunner.apply_task_result(coord, task, :ok)
    end

    test "tasks are left in running", %{run: run, task: task} do
      sec_task = task_fixture(%{run_id: run.id, name: "second_task"})

      coord = %RetryingRunner{
        running: MapSet.new([task.id, sec_task.id]),
        retrying: %{}
      }

      remaining = MapSet.new([sec_task.id])

      assert {:continue, %RetryingRunner{running: ^remaining, retrying: %{}}} =
               RetryingRunner.apply_task_result(coord, task, :ok)
    end
  end
end
