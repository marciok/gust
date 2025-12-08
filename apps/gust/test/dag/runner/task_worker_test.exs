defmodule DAG.Runner.TaskWorkerTest do
  require Logger
  use Gust.DataCase, async: false
  import Gust.FlowsFixtures

  import Mox

  setup :verify_on_exit!
  setup :set_mox_from_context

  setup do
    task_name = "hi"
    dag = dag_fixture()
    run = run_fixture(%{dag_id: dag.id})
    task = task_fixture(%{run_id: run.id, name: task_name})
    task_id = task.id
    task_attempt = task.attempt

    Gust.DAGLoggerMock
    |> expect(:set_task, fn ^task_id, ^task_attempt -> nil end)
    |> expect(:unset, fn -> nil end)

    %{task: task}
  end

  describe "handle_continue/2 when :init_run is given" do
    test "run task with context", %{task: task} do
      dag_content = """
      defmodule DagToBeRun do
        def hi(args) do
          args
        end
      end
      """

      [{mod, _bin}] = Code.compile_string(dag_content)

      run_id = task.run_id
      task_id = task.id

      worker_pid =
        start_link_supervised!(
          {Gust.DAG.Runner.TaskWorker, %{task: task, mod: mod, stage_pid: self(), opts: %{}}}
        )

      ref = Process.monitor(worker_pid)
      assert_receive {:task_result, %{run_id: ^run_id}, ^task_id, :ok}, 200
      assert_receive {:DOWN, ^ref, :process, _pid, :normal}, 200

      on_exit(fn ->
        :code.purge(mod)
        :code.delete(mod)
      end)
    end

    test "run succeed", %{task: task} do
      task_id = task.id
      result = "i_am_done"

      dag_content = """
        defmodule MySuccessfulDagOne do
          use Gust.DSL
          require Logger

          task :#{task.name} do
            Process.sleep(100)
            "#{result}"
          end
        end
      """

      [{mod, _bin}] = Code.compile_string(dag_content)

      worker_pid =
        start_link_supervised!(
          {Gust.DAG.Runner.TaskWorker, %{task: task, mod: mod, stage_pid: self(), opts: %{}}}
        )

      ref = Process.monitor(worker_pid)
      assert_receive {:task_result, ^result, ^task_id, :ok}, 200
      assert_receive {:DOWN, ^ref, :process, _pid, :normal}, 200

      on_exit(fn ->
        :code.purge(mod)
        :code.delete(mod)
      end)
    end

    test "run fails", %{task: task} do
      task_id = task.id
      error_message = "Ops.."

      dag_content = """
        defmodule MySuccessfulDag do
          use Gust.DSL

          task :#{task.name} do
            Process.sleep(100)
            raise "#{error_message}"
          end
        end
      """

      [{mod, _bin}] = Code.compile_string(dag_content)

      worker_pid =
        start_link_supervised!(
          {Gust.DAG.Runner.TaskWorker, %{task: task, mod: mod, stage_pid: self(), opts: %{}}}
        )

      ref = Process.monitor(worker_pid)

      result = %RuntimeError{message: error_message, __exception__: true}

      assert_receive {:task_result, ^result, ^task_id, :error}, 200
      assert_receive {:DOWN, ^ref, :process, _pid, :normal}, 200

      on_exit(fn ->
        :code.purge(mod)
        :code.delete(mod)
      end)
    end

    test "store result is set but type is not map", %{task: task} do
      task_id = task.id
      error_message = "Task returned :i_am_no_map but store_result requires a map"

      dag_content = """
        defmodule MySuccessfulDag do
          use Gust.DSL

          task :#{task.name}, store_result: true do
            Process.sleep(100)
            :i_am_no_map
          end
        end
      """

      [{mod, _bin}] = Code.compile_string(dag_content)

      worker_pid =
        start_link_supervised!(
          {Gust.DAG.Runner.TaskWorker,
           %{task: task, mod: mod, stage_pid: self(), opts: %{store_result: true}}}
        )

      ref = Process.monitor(worker_pid)

      result = %RuntimeError{message: error_message, __exception__: true}

      assert_receive {:task_result, ^result, ^task_id, :error}, 200
      assert_receive {:DOWN, ^ref, :process, _pid, :normal}, 200

      on_exit(fn ->
        :code.purge(mod)
        :code.delete(mod)
      end)
    end
  end
end
