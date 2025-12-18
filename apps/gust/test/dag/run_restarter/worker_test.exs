defmodule DAG.RunRestarter.WorkerTest do
  alias Gust.Flows
  use Gust.DataCase

  import Gust.FlowsFixtures
  import Mox

  alias Gust.DAG.RunRestarter.Worker

  setup :verify_on_exit!
  setup :set_mox_from_context

  setup do
    dag = dag_fixture(%{name: "restart_me"})
    dag_fixture(%{name: "other_dag"})
    restart_run = run_fixture(%{dag_id: dag.id, status: :running})
    run_fixture(%{dag_id: dag.id})

    {:ok, dag: dag, restart_run: restart_run}
  end

  describe "handle_call/2 for {:start_run, dag_id}" do
    test "start_child for enabled dag", %{
      dag: dag
    } do
      start_link_supervised!(Worker)
      dag_def = %Gust.DAG.Definition{name: dag.name}
      dag_id = dag.id

      Gust.DAGRunnerSupervisorMock
      |> expect(:start_child, fn %Flows.Run{dag_id: ^dag_id}, ^dag_def ->
        {:ok, spawn(fn -> :ok end)}
      end)

      Gust.DAGLoaderMock
      |> expect(:get_definition, fn _dag_id ->
        {:ok, dag_def}
      end)

      assert %Flows.Run{status: :created, dag_id: ^dag_id} =
               Worker.start_dag(dag.id)
    end

    test "do not start_child for errored dag", %{
      dag: dag
    } do
      dag_def = %Gust.DAG.Definition{name: dag.name, error: %{message: "ops.."}}

      Gust.DAGLoaderMock
      |> expect(:get_definition, fn _dag_id ->
        {:ok, dag_def}
      end)

      start_link_supervised!(Worker)

      assert is_nil(Worker.start_dag(dag.id))
    end

    test "do not start_child for disabled dag, enqueue run", %{
      dag: dag
    } do
      start_link_supervised!(Worker)
      {:ok, dag} = Flows.toggle_enabled(dag)
      dag_id = dag.id

      assert %Flows.Run{status: :enqueued, dag_id: ^dag_id} = Worker.start_dag(dag.id)
    end
  end

  describe "handle_call/2 for {:restart_run, run}" do
    test "restart run ", %{dag: dag} do
      run = run_fixture(%{dag_id: dag.id})
      run_id = run.id
      dag_def = %Gust.DAG.Definition{name: dag.name}
      task = task_fixture(%{run_id: run.id, name: "my_task", status: :failed})

      Gust.DAGLoaderMock
      |> expect(:get_definition, fn _dag_id ->
        {:ok, dag_def}
      end)

      Gust.DAGRunnerSupervisorMock
      |> expect(:start_child, fn %{id: ^run_id}, _dag_def ->
        {:ok, spawn(fn -> :ok end)}
      end)

      start_link_supervised!(Worker)

      run = Worker.restart_run(run)

      assert %{status: :created} = Flows.get_task!(task.id)
      assert %{status: :running} = Flows.get_run!(run.id)
    end
  end

  describe "handle_call/2 for {:restart_task, graph, task}" do
    test "restart task with downstream", %{dag: dag} do
      dag_def = %Gust.DAG.Definition{name: dag.name}
      run = run_fixture(%{dag_id: dag.id})
      task = task_fixture(%{run_id: run.id, name: "wait", status: :failed})
      task_second = task_fixture(%{run_id: run.id, name: "bye", status: :failed})

      Gust.DAGLoaderMock
      |> expect(:get_definition, fn _dag_id ->
        {:ok, dag_def}
      end)

      Gust.DAGRunnerSupervisorMock
      |> expect(:start_child, fn _run, _dag_def ->
        {:ok, spawn(fn -> :ok end)}
      end)

      start_link_supervised!(Worker)

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

      [second_restarted, restarted_task] = Worker.restart_task(graph, task)

      assert restarted_task.id == task.id
      assert restarted_task.status == :created
      assert second_restarted.id == task_second.id
      assert second_restarted.status == :created

      assert %{status: :running} = Flows.get_run!(run.id)
    end
  end

  describe "handle_info/2 for {:restart_enqueued, dag_id}" do
    test "do not enqueued runs for errored definitions", %{dag: dag} do
      dag_id = dag.id
      dag_def = %Gust.DAG.Definition{error: %CompileError{description: "oops"}}
      run_fixture(%{dag_id: dag_id, status: :enqueued})

      Gust.DAGLoaderMock
      |> expect(:get_definition, fn ^dag_id ->
        {:ok, dag_def}
      end)

      pid = start_link_supervised!(Worker)
      Worker.restart_enqueued(dag.id)
      Process.sleep(200)

      refute_received {:DOWN, _, :process, ^pid, _}, 200
    end

    test "do not enqueued runs for dag with errors", %{dag: dag} do
      dag_id = dag.id

      Gust.DAGLoaderMock
      |> expect(:get_definition, fn ^dag_id ->
        {:error, {}}
      end)

      pid = start_link_supervised!(Worker)
      Worker.restart_enqueued(dag.id)
      Process.sleep(200)

      refute_received {:DOWN, _, :process, ^pid, _}, 200
    end

    test "reloads dag_def and starts enqueued runs", %{dag: dag} do
      dag_id = dag.id
      dag_def = %Gust.DAG.Definition{name: dag.name}

      Gust.DAGLoaderMock
      |> expect(:get_definition, fn ^dag_id ->
        {:ok, dag_def}
      end)

      enqueued_run_1 = run_fixture(%{dag_id: dag_id, status: :enqueued})
      enqueued_run_2 = run_fixture(%{dag_id: dag_id, status: :enqueued})

      Gust.DAGRunnerSupervisorMock
      |> expect(:start_child, fn ^enqueued_run_1, ^dag_def -> {:ok, spawn(fn -> :ok end)} end)
      |> expect(:start_child, fn ^enqueued_run_2, ^dag_def -> {:ok, spawn(fn -> :ok end)} end)

      pid = start_link_supervised!(Worker)
      Worker.restart_enqueued(dag.id)
      Process.sleep(200)

      refute_received {:DOWN, _, :process, ^pid, _}, 200
    end
  end

  describe "handle_call/2 for {:restart, dags}" do
    test "does not restart there is not dag_def", %{dag: dag} do
      pid = start_link_supervised!(Worker)
      ref = Process.monitor(pid)

      assert [] == Worker.restart_dags(%{dag.id => {:error, {}}})

      refute_receive({:DOWN, ^ref, :process, ^pid, :normal}, 200)
    end

    test "does not restart if dag_def has errors", %{dag: dag} do
      dag_def = %Gust.DAG.Definition{error: %CompileError{description: "oops"}}

      pid = start_link_supervised!(Worker)
      ref = Process.monitor(pid)

      assert [] == Worker.restart_dags(%{dag.id => {:ok, dag_def}})

      refute_receive({:DOWN, ^ref, :process, ^pid, :normal}, 200)
    end

    test "restarts running runs for given dags", %{dag: dag, restart_run: restart_run} do
      dag_def = %Gust.DAG.Definition{error: %{}}
      restart_retrying_run = run_fixture(%{dag_id: dag.id, status: :retrying})

      Gust.DAGRunnerSupervisorMock
      |> expect(:start_child, fn ^restart_run, ^dag_def -> {:ok, spawn(fn -> :ok end)} end)
      |> expect(:start_child, fn ^restart_retrying_run, ^dag_def ->
        {:ok, spawn(fn -> :ok end)}
      end)

      pid = start_link_supervised!(Worker)
      ref = Process.monitor(pid)

      assert [^restart_run, ^restart_retrying_run] =
               Worker.restart_dags(%{dag.id => {:ok, dag_def}})

      refute_receive {:DOWN, ^ref, :process, ^pid, :normal}, 200
    end
  end
end
