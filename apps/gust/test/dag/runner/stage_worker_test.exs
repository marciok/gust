defmodule Dag.Runner.StageWorkerTest do
  alias Gust.Flows
  use Gust.DataCase, async: false

  import Gust.FlowsFixtures

  import Mox

  setup :verify_on_exit!
  setup :set_mox_from_context

  setup do
    dag = dag_fixture()
    run = run_fixture(%{dag_id: dag.id})
    task_name = "tool"

    dag_def = %Gust.DAG.Definition{
      mod: MyDag,
      stages: [],
      tasks: %{task_name => %{upstream: MapSet.new([]), store_result: true}}
    }

    task = task_fixture(%{run_id: run.id, name: task_name})

    Registry.register(Gust.Registry, "dag_run_#{run.id}", nil)

    %{task: task, run: run, dag_def: dag_def}
  end

  def upstream_did_not_fail(%{run: _run, dag_def: dag_def, task: task}) do
    mod = dag_def.mod

    Gust.DAGTaskRunnerSupervisorMock
    |> expect(:start_child, fn _task, ^mod, _pid, _opts ->
      {:ok, spawn(fn -> Process.sleep(10) end)}
    end)

    task_id = task.id

    Gust.DAGStageCoordinatorMock
    |> expect(:new, fn [^task_id] -> %{} end)
    |> expect(:process_task, fn %Flows.Task{id: ^task_id}, _tasks -> :ok end)

    :ok
  end

  def upstream_failed(%{task: task}) do
    task_id = task.id

    Gust.DAGStageCoordinatorMock
    |> expect(:new, fn [^task_id] -> %{} end)
    |> expect(:process_task, fn %Flows.Task{id: ^task_id}, _tasks -> :upstream_failed end)

    :ok
  end

  describe "handle_continue/2 when task was already processed" do
    test "does update task result", %{
      run: run,
      dag_def: dag_def,
      task: task
    } do
      task_id = task.id

      prev_result = %{"prev_result" => true}
      {:ok, task} = Flows.update_task_result(task, prev_result)

      Gust.DAGStageCoordinatorMock
      |> expect(:new, fn [^task_id] -> %{} end)
      |> expect(:process_task, fn %Flows.Task{id: ^task_id}, _tasks -> :already_processed end)

      Gust.PubSub.subscribe_run(run.id)
      task_id = task.id
      run_id = run.id

      Gust.DAGStageCoordinatorMock
      |> expect(:apply_task_result, fn _coord, _task, :already_processed ->
        {:finished, %{running: %{}}}
      end)

      runner_pid =
        start_link_supervised!(
          {Gust.DAG.Runner.StageWorker, %{stage: [task_id], dag_def: dag_def}}
        )

      ref = Process.monitor(runner_pid)

      refute_receive {:dag, :run_status, %{run_id: ^run_id, status: _status}}, 400

      assert Flows.get_task!(task_id).result == prev_result

      assert_receive {:DOWN, ^ref, :process, _pid, :normal}, 400
    end
  end

  describe "handle_continue/2 when upstream did fail" do
    setup [:upstream_failed]

    test "tasks finished unsuccessfull and stage is finished", %{
      run: run,
      dag_def: dag_def,
      task: task
    } do
      Gust.PubSub.subscribe_run(run.id)
      task_id = task.id
      run_id = run.id

      Gust.DAGStageCoordinatorMock
      |> expect(:apply_task_result, fn _coord, _task, :upstream_failed ->
        {:finished, %{running: %{}}}
      end)

      runner_pid =
        start_link_supervised!(
          {Gust.DAG.Runner.StageWorker, %{stage: [task_id], dag_def: dag_def}}
        )

      ref = Process.monitor(runner_pid)

      assert_receive {:dag, :run_status, %{run_id: ^run_id, status: :upstream_failed}},
                     400

      assert Flows.get_task!(task_id).status == :upstream_failed

      assert_receive {:stage_completed, :upstream_failed}, 400
      assert_receive {:DOWN, ^ref, :process, _pid, :normal}, 400
    end

    test "tasks finished unsuccessfull but stage continues", %{
      run: run,
      dag_def: dag_def,
      task: task
    } do
      Gust.PubSub.subscribe_run(run.id)
      task_id = task.id
      run_id = run.id

      Gust.DAGStageCoordinatorMock
      |> expect(:apply_task_result, fn _coord, _task, :upstream_failed ->
        {:continue, %{running: %{}}}
      end)

      runner_pid =
        start_link_supervised!(
          {Gust.DAG.Runner.StageWorker, %{stage: [task_id], dag_def: dag_def}}
        )

      ref = Process.monitor(runner_pid)

      assert_receive {:dag, :run_status, %{run_id: ^run_id, status: :upstream_failed}},
                     400

      assert Flows.get_task!(task_id).status == :upstream_failed

      refute_receive {:stage_completed, :upstream_failed}, 400
      refute_receive {:DOWN, ^ref, :process, _pid, :normal}, 400
    end
  end

  describe "handle_continue/2 when upstream did not fail" do
    setup [:upstream_did_not_fail]

    test "tasks finished as reschedule and succeeded", %{task: task, run: run, dag_def: dag_def} do
      mod = dag_def.mod
      reschedule_time = 0
      task_id = task.id
      run_id = run.id

      Gust.DAGStageCoordinatorMock
      |> expect(:apply_task_result, fn _coord, _task, :error ->
        {:reschedule, %{running: %{}}, task, reschedule_time}
      end)
      |> expect(:put_running, fn _coord, ^task_id ->
        %{running: MapSet.new([task_id])}
      end)
      |> expect(:update_restart_timer, fn coord, %{id: ^task_id}, _ref ->
        coord
      end)

      Gust.PubSub.subscribe_run(run.id)

      runner_pid =
        start_link_supervised!(
          {Gust.DAG.Runner.StageWorker, %{stage: [task_id], dag_def: dag_def}}
        )

      assert_receive {:dag, :run_status, %{run_id: ^run_id, status: :running}}, 300
      assert Flows.get_task!(task_id).status == :running

      ref = Process.monitor(runner_pid)

      error = %Ecto.CastError{message: "ops"}
      send(runner_pid, {:task_result, error, task.id, :error})

      Gust.DAGTaskRunnerSupervisorMock
      |> expect(:start_child, fn _task, ^mod, _pid, _opts ->
        {:ok, spawn(fn -> Process.sleep(10) end)}
      end)

      Gust.DAGStageCoordinatorMock
      |> expect(:apply_task_result, fn _coord, _task, :ok ->
        {:finished, %{running: %{}}}
      end)

      assert_receive {:dag, :run_status, %{run_id: ^run_id, status: :retrying}}, 200
      assert Flows.get_task!(task_id).status == :retrying

      Process.sleep(reschedule_time + 200)
      send(runner_pid, {:task_result, %{}, task.id, :ok})

      assert_receive {:dag, :run_status, %{run_id: ^run_id, status: :running}},
                     reschedule_time + 300

      assert Flows.get_task!(task_id).status == :running
      assert Flows.get_task!(task_id).attempt == 2

      assert_receive {:dag, :run_status, %{run_id: ^run_id, status: :succeeded}},
                     reschedule_time + 400

      assert Flows.get_task!(task_id).status == :succeeded

      assert_receive {:stage_completed, :ok}, reschedule_time + 300
      assert_receive {:DOWN, ^ref, :process, _pid, :normal}, reschedule_time + 300
    end

    test "tasks is cancelled", %{
      run: run,
      dag_def: dag_def,
      task: task
    } do
      Gust.PubSub.subscribe_run(run.id)
      task_id = task.id
      run_id = run.id

      ref = make_ref()

      Gust.DAGStageCoordinatorMock
      |> expect(:apply_task_result, 2, fn _coord, _task_id, :cancelled ->
        {:continue,
         %{
           running: MapSet.new(["another_running_task_id"]),
           retrying: %{
             task_id => %{restart_timer: ref}
           }
         }}
      end)

      runner_pid =
        start_link_supervised!(
          {Gust.DAG.Runner.StageWorker, %{stage: [task_id], dag_def: dag_def}}
        )

      ref = Process.monitor(runner_pid)

      send(runner_pid, {:task_result, nil, task_id, :cancelled})
      send(runner_pid, {:cancel_timer, task_id, :cancelled})

      assert_receive {:dag, :run_status, %{run_id: ^run_id, status: :failed}}, 400
      assert Flows.get_task!(task_id).status == :failed
      assert Flows.get_task!(task_id).error == %{}

      refute_receive {:stage_completed, :ok}, 400
      refute_receive {:DOWN, ^ref, :process, _pid, :normal}, 400
    end

    test "tasks finished unsuccessfull but stage continues", %{
      run: run,
      dag_def: dag_def,
      task: task
    } do
      Gust.PubSub.subscribe_run(run.id)
      task_id = task.id
      run_id = run.id

      Gust.DAGStageCoordinatorMock
      |> expect(:apply_task_result, fn _coord, _task_id, :error ->
        {:continue, %{running: MapSet.new(["another_running_task_id"])}}
      end)

      runner_pid =
        start_link_supervised!(
          {Gust.DAG.Runner.StageWorker, %{stage: [task_id], dag_def: dag_def}}
        )

      ref = Process.monitor(runner_pid)
      error_msg = "ops"
      error = %Ecto.Query.CastError{message: error_msg}

      send(runner_pid, {:task_result, error, task_id, :error})

      assert_receive {:dag, :run_status, %{run_id: ^run_id, status: :failed}}, 400
      assert Flows.get_task!(task_id).status == :failed

      assert Flows.get_task!(task_id).error == %{
               "message" => error_msg,
               "type" => "Ecto.Query.CastError"
             }

      refute_receive {:stage_completed, :ok}, 400
      refute_receive {:DOWN, ^ref, :process, _pid, :normal}, 400
    end

    test "tasks save results", %{
      run: run,
      dag_def: dag_def,
      task: task
    } do
      Gust.PubSub.subscribe_run(run.id)
      task_id = task.id
      run_id = run.id

      {:ok, _task} = Flows.update_task_error(task, %{error: "yes"})

      Gust.DAGStageCoordinatorMock
      |> expect(:apply_task_result, fn _coord, _task_id, :ok ->
        {:continue, %{running: MapSet.new(["another_running_task_id"])}}
      end)

      runner_pid =
        start_link_supervised!(
          {Gust.DAG.Runner.StageWorker, %{stage: [task_id], dag_def: dag_def}}
        )

      ref = Process.monitor(runner_pid)
      result = %{"ended" => "ok"}

      send(runner_pid, {:task_result, result, task_id, :ok})

      assert_receive {:dag, :run_status, %{run_id: ^run_id, status: :succeeded}}, 400
      assert Flows.get_task!(task_id).status == :succeeded
      assert Flows.get_task!(task_id).result == result
      assert Flows.get_task!(task_id).error == %{}

      refute_receive {:stage_completed, :ok}, 400
      refute_receive {:DOWN, ^ref, :process, _pid, :normal}, 400
    end

    test "tasks finished successfull but stage continues", %{
      run: run,
      dag_def: dag_def,
      task: task
    } do
      Gust.PubSub.subscribe_run(run.id)
      task_id = task.id
      run_id = run.id
      dag_def = %{dag_def | tasks: %{task.name => %{store_result: false}}}

      Gust.DAGStageCoordinatorMock
      |> expect(:apply_task_result, fn _coord, _task_id, :ok ->
        {:continue, %{running: MapSet.new(["another_running_task_id"])}}
      end)

      runner_pid =
        start_link_supervised!(
          {Gust.DAG.Runner.StageWorker, %{stage: [task_id], dag_def: dag_def}}
        )

      ref = Process.monitor(runner_pid)

      result = %{"ended" => "ok"}
      Flows.update_task_error(task, %{some: "error"})

      send(runner_pid, {:task_result, result, task_id, :ok})

      assert_receive {:dag, :run_status, %{run_id: ^run_id, status: :succeeded}}, 400
      assert Flows.get_task!(task_id).status == :succeeded
      assert Flows.get_task!(task_id).result == %{}
      assert Flows.get_task!(task_id).error == %{}

      refute_receive {:stage_completed, :ok}, 400
      refute_receive {:DOWN, ^ref, :process, _pid, :normal}, 400
    end

    test "tasks finished", %{run: run, dag_def: dag_def, task: task} do
      Gust.PubSub.subscribe_run(run.id)
      task_id = task.id
      run_id = run.id

      Gust.DAGStageCoordinatorMock
      |> expect(:apply_task_result, fn _coord, task_resulted, :error ->
        assert task_resulted.id == task.id
        {:finished, %{running: MapSet.new([])}}
      end)

      assert Flows.get_task!(task_id).status == :created

      error = %Ecto.CastError{message: "ops"}

      runner_pid =
        start_link_supervised!(
          {Gust.DAG.Runner.StageWorker, %{stage: [task_id], dag_def: dag_def}}
        )

      ref = Process.monitor(runner_pid)

      send(runner_pid, {:task_result, error, task_id, :error})

      assert_receive {:stage_completed, :error}, 400
      assert Flows.get_task!(task_id).status == :failed
      assert_receive {:dag, :run_status, %{run_id: ^run_id, status: :failed}}, 400

      assert_receive {:DOWN, ^ref, :process, _pid, :normal}, 400
    end
  end
end
