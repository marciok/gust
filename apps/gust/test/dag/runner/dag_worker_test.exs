defmodule DAG.Runner.DagWorkerTest do
  use Gust.DataCase, async: false

  import Mox
  import Gust.FlowsFixtures
  alias Gust.{Flows, Repo}

  setup :verify_on_exit!
  setup :set_mox_from_context

  setup do
    dag = dag_fixture()
    run = run_fixture(%{dag_id: dag.id})

    dag_def = %Gust.DAG.Definition{
      mod: MyDag,
      stages: [["hi", "hey", "ho"], ["bye"]]
    }

    Gust.DAGCompilerMock
    |> expect(:compile, fn dag_def ->
      dag_def.mod
    end)

    %{run: run, dag_def: dag_def}
  end

  describe "handle_info/2" do
    test "start stage worker", %{run: run, dag_def: dag_def} do
      Gust.PubSub.subscribe_run(run.id)
      Gust.PubSub.subscribe_runs_for_dag(run.dag_id)

      hi_task_id = task_fixture(%{name: "hi", status: :succeeded, run_id: run.id}).id
      hey_task_id = task_fixture(%{name: "hey", status: :running, run_id: run.id}).id
      run_id = run.id

      Gust.DAGStageRunnerSupervisorMock
      |> expect(:start_child, fn ^dag_def, [^hi_task_id, ^hey_task_id, _ho_task], _pid ->
        {:ok, spawn(fn -> Process.sleep(10) end)}
      end)

      runner_pid =
        start_supervised!({Gust.DAG.Runner.DAGWorker, %{run: run, dag_def: dag_def}})

      ref = Process.monitor(runner_pid)

      assert_receive {:dag, :run_started, %{run_id: ^run_id}}, 200

      assert_receive {:dag, :run_status, %{run_id: ^run_id, status: :running}}, 200
      assert Repo.get!(Flows.Run, run.id).status == :running
      assert Flows.get_task!(hey_task_id).status == :created

      refute_receive {:DOWN, ^ref, :process, _pid, :normal}, 200
    end
  end

  describe "handle_info/2, stage_completed unsuccessfully" do
    test "upstream failed", %{run: run, dag_def: dag_def} do
      Gust.PubSub.subscribe_run(run.id)
      last_stage = dag_def.stages |> List.last()
      dag_def = %Gust.DAG.Definition{dag_def | stages: [last_stage]}
      run_id = run.id

      Gust.DAGCompilerMock
      |> expect(:purge, fn _mod ->
        nil
      end)

      Gust.DAGStageRunnerSupervisorMock
      |> expect(:start_child, fn ^dag_def, task_ids, _pid ->
        for task_id <- task_ids do
          task = Flows.get_task!(task_id)
          assert task.name in last_stage
          assert task.run_id == run.id
        end

        {:ok, spawn(fn -> Process.sleep(10) end)}
      end)

      runner_pid =
        start_supervised!({Gust.DAG.Runner.DAGWorker, %{run: run, dag_def: dag_def}})

      ref = Process.monitor(runner_pid)

      send(runner_pid, {:stage_completed, :upstream_failed})

      assert_receive {:dag, :run_status, %{run_id: ^run_id}}, 400
      assert Repo.get!(Flows.Run, run.id).status == :failed

      assert_receive {:DOWN, ^ref, :process, _pid, :normal}, 200
    end

    test "next stage is empty", %{run: run, dag_def: dag_def} do
      Gust.PubSub.subscribe_run(run.id)
      last_stage = dag_def.stages |> List.last()

      defmodule TestModCallback do
        def start_agent do
          Agent.start_link(fn -> [] end, name: __MODULE__)
        end

        def callback(status, run) do
          Agent.update(__MODULE__, fn calls -> [{status, run.id} | calls] end)
          {status, run.id}
        end

        def calls do
          Agent.get(__MODULE__, & &1)
        end
      end

      test_mod = TestModCallback
      {:ok, _} = TestModCallback.start_agent()

      on_exit(fn -> :code.purge(test_mod) end)

      dag_def = %Gust.DAG.Definition{
        dag_def
        | stages: [last_stage],
          mod: TestModCallback,
          options: [on_finished_callback: :callback]
      }

      run_id = run.id

      Gust.DAGCompilerMock
      |> expect(:purge, fn _mod ->
        nil
      end)

      Gust.DAGStageRunnerSupervisorMock
      |> expect(:start_child, fn ^dag_def, task_ids, _pid ->
        for task_id <- task_ids do
          task = Flows.get_task!(task_id)
          assert task.name in last_stage
          assert task.run_id == run.id
        end

        {:ok, spawn(fn -> Process.sleep(10) end)}
      end)

      runner_pid =
        start_supervised!({Gust.DAG.Runner.DAGWorker, %{run: run, dag_def: dag_def}})

      ref = Process.monitor(runner_pid)

      send(runner_pid, {:stage_completed, :error})

      assert_receive {:dag, :run_status, %{run_id: ^run_id, status: :failed}}, 400
      assert Repo.get!(Flows.Run, run.id).status == :failed

      assert_receive {:DOWN, ^ref, :process, _pid, :normal}, 200
      assert [{:error, ^run_id}] = TestModCallback.calls()
    end
  end

  describe "handle_info/2, when run have running and done tasks " do
    test "start_child with restarting tasks", %{run: run, dag_def: dag_def} do
      hey_t = task_fixture(%{run_id: run.id, name: "hey", status: :running})
      ho_t = task_fixture(%{run_id: run.id, name: "ho", status: :failed})

      Gust.DAGStageRunnerSupervisorMock
      |> expect(:start_child, fn ^dag_def, task_ids, _pid ->
        [t1, t2, t3] = task_ids

        assert t2 == hey_t.id
        assert Flows.get_task!(t2).status == :created
        assert t3 == ho_t.id
        assert Flows.get_task!(t1).name == "hi"

        {:ok, spawn(fn -> Process.sleep(10) end)}
      end)

      runner_pid =
        start_supervised!({Gust.DAG.Runner.DAGWorker, %{run: run, dag_def: dag_def}})

      ref = Process.monitor(runner_pid)

      refute_receive {:DOWN, ^ref, :process, _pid, :normal}, 200
    end
  end

  describe "handle_info/2, stage_completed successfully" do
    test "next stage start", %{run: run, dag_def: dag_def} do
      first_stage = dag_def.stages |> List.first()
      last_stage = dag_def.stages |> List.last()

      Gust.DAGStageRunnerSupervisorMock
      |> expect(:start_child, fn ^dag_def, task_ids, _pid ->
        for task_id <- task_ids do
          task = Flows.get_task!(task_id)
          assert task.name in first_stage
          assert task.run_id == run.id
        end

        {:ok, spawn(fn -> Process.sleep(10) end)}
      end)

      Gust.DAGStageRunnerSupervisorMock
      |> expect(:start_child, fn ^dag_def, task_ids, _pid ->
        for task_id <- task_ids do
          task = Flows.get_task!(task_id)
          assert task.name in last_stage
          assert task.run_id == run.id
        end

        {:ok, spawn(fn -> Process.sleep(10) end)}
      end)

      runner_pid =
        start_supervised!({Gust.DAG.Runner.DAGWorker, %{run: run, dag_def: dag_def}})

      ref = Process.monitor(runner_pid)

      send(runner_pid, {:stage_completed, :ok})

      refute_receive {:DOWN, ^ref, :process, _pid, :normal}, 200
    end

    test "next stage is empty", %{run: run, dag_def: dag_def} do
      Gust.PubSub.subscribe_run(run.id)
      last_stage = dag_def.stages |> List.last()
      dag_def = %Gust.DAG.Definition{dag_def | stages: [last_stage]}
      run_id = run.id

      Gust.DAGCompilerMock
      |> expect(:purge, fn _mod ->
        nil
      end)

      Gust.DAGStageRunnerSupervisorMock
      |> expect(:start_child, fn ^dag_def, task_ids, _pid ->
        for task_id <- task_ids do
          task = Flows.get_task!(task_id)
          assert task.name in last_stage
          assert task.run_id == run.id
        end

        {:ok, spawn(fn -> Process.sleep(10) end)}
      end)

      runner_pid =
        start_supervised!({Gust.DAG.Runner.DAGWorker, %{run: run, dag_def: dag_def}})

      ref = Process.monitor(runner_pid)

      send(runner_pid, {:stage_completed, :ok})

      assert_receive {:dag, :run_status, %{run_id: ^run_id, status: :succeeded}}, 400
      assert Repo.get!(Flows.Run, run.id).status == :succeeded

      assert_receive {:DOWN, ^ref, :process, _pid, :normal}, 200
    end
  end
end
