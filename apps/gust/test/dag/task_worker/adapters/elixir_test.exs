defmodule DAG.TaskWorker.Adapters.ElixirTest do
  @moduledoc false

  require Logger
  use Gust.DataCase, async: false
  import Gust.FlowsFixtures
  alias Gust.DAG.TaskWorker.Adapters.Elixir, as: TaskWorker

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

  defp compile_dag!(dag_content) do
    [{mod, _bin}] = Code.compile_string(dag_content)

    on_exit(fn ->
      :code.purge(mod)
      :code.delete(mod)
    end)

    mod
  end

  defp start_worker_and_monitor!(task, mod, opts) do
    dag_def = %Gust.DAG.Definition{mod: mod, adapter: :elixir}

    worker_pid =
      start_link_supervised!(
        {TaskWorker, %{task: task, dag_def: dag_def, stage_pid: self(), opts: opts}}
      )

    Process.monitor(worker_pid)
  end

  defp assert_worker_result(ref, task_id, result, status) do
    assert_receive {:task_result, ^result, ^task_id, ^status}, 200
    assert_receive {:DOWN, ^ref, :process, _pid, :normal}, 200
  end

  describe "handle_continue/2 when :run is given" do
    test "run task with context", %{task: task} do
      dag_content = """
      defmodule DagToBeRun do
        def hi(args) do
          args
        end
      end
      """

      mod = compile_dag!(dag_content)
      ref = start_worker_and_monitor!(task, mod, %{store_result: false, skip_if: nil})

      assert_worker_result(ref, task.id, %{run_id: task.run_id}, :ok)
    end

    test "runs mapped task with params in context", %{task: task} do
      params = %{"model" => "gpt-5"}
      mapped_task = %{task | map_index: 1, params: params}

      dag_content = """
      defmodule MappedTaskDag do
        def hi(%{params: %{"model" => model}}) do
          %{model: model}
        end
      end
      """

      mod = compile_dag!(dag_content)

      ref =
        start_worker_and_monitor!(mapped_task, mod, %{
          store_result: true,
          skip_if: nil
        })

      assert_worker_result(ref, task.id, %{model: "gpt-5"}, :ok)
    end

    test "run succeed", %{task: task} do
      result = "i_am_done"

      dag_content = """
        defmodule SuccessfulTaskDag do
          use Gust.DSL
          require Logger

          task :#{task.name} do
            Process.sleep(100)
            %{res: "#{result}"}
          end
        end
      """

      mod = compile_dag!(dag_content)
      ref = start_worker_and_monitor!(task, mod, %{store_result: true})

      assert_worker_result(ref, task.id, %{res: result}, :ok)
    end

    test "wraps a list result when storing the result", %{task: task} do
      dag_content = """
        defmodule ListResultTaskDag do
          use Gust.DSL

          task :#{task.name}, store_result: true do
            [%{id: 1}, %{id: 2}]
          end
        end
      """

      mod = compile_dag!(dag_content)
      ref = start_worker_and_monitor!(task, mod, %{store_result: true})

      assert_worker_result(
        ref,
        task.id,
        %{gust_task_items: [%{id: 1}, %{id: 2}]},
        :ok
      )
    end

    test "run fails", %{task: task} do
      error_message = "Ops.."

      dag_content = """
        defmodule FailingTaskDag do
          use Gust.DSL

          task :#{task.name} do
            Process.sleep(100)
            raise "#{error_message}"
          end
        end
      """

      mod = compile_dag!(dag_content)
      ref = start_worker_and_monitor!(task, mod, %{store_result: false})
      result = %RuntimeError{message: error_message, __exception__: true}

      assert_worker_result(ref, task.id, result, :error)
    end

    test "skip_if is set and return is false", %{task: task} do
      skip_if_fn = :skip_me

      dag_content = """
        defmodule SkipIfFalseDag do
          use Gust.DSL

          def #{skip_if_fn}(_ctx), do: false

          task :#{task.name}, skip_if: :#{skip_if_fn} do
            Process.sleep(100)
            :good
          end
        end
      """

      mod = compile_dag!(dag_content)
      ref = start_worker_and_monitor!(task, mod, %{skip_if: skip_if_fn, store_result: false})

      assert_worker_result(ref, task.id, :good, :ok)
    end

    test "skip_if is set and return is true", %{task: task} do
      skip_if_fn = :skip_me

      dag_content = """
        defmodule SkipIfTrueDag do
          use Gust.DSL

          def #{skip_if_fn}(%{run_id: run_id}), do: run_id == #{task.run_id}

          task :#{task.name}, skip_if: :#{skip_if_fn} do
            Process.sleep(100)
            :ok
          end
        end
      """

      mod = compile_dag!(dag_content)
      ref = start_worker_and_monitor!(task, mod, %{skip_if: skip_if_fn})

      assert_worker_result(ref, task.id, %{}, :skipped)
    end

    test "skip_if is set but type is not a boolean", %{task: task} do
      error_message = ":skip_if returned 123 but requires a boolean"
      skip_if_fn = :not_boolean

      dag_content = """
        defmodule SkipIfInvalidReturnDag do
          use Gust.DSL

          def #{skip_if_fn}(_ctx), do: 123

          task :#{task.name}, skip_if: :#{skip_if_fn} do
            Process.sleep(100)
            :ok
          end
        end
      """

      mod = compile_dag!(dag_content)
      ref = start_worker_and_monitor!(task, mod, %{skip_if: skip_if_fn})
      result = %RuntimeError{message: error_message, __exception__: true}

      assert_worker_result(ref, task.id, result, :error)
    end

    test "skip_if is set but function call fails", %{task: task} do
      error_message = "Failling here"
      skip_if_fn = :fail_me

      dag_content = """
        defmodule SkipIfInvalidReturnDag do
          use Gust.DSL

          def #{skip_if_fn}(_ctx), do: raise "#{error_message}"

          task :#{task.name}, skip_if: :#{skip_if_fn} do
            Process.sleep(100)
            :ok
          end
        end
      """

      mod = compile_dag!(dag_content)
      ref = start_worker_and_monitor!(task, mod, %{skip_if: skip_if_fn})
      result = %RuntimeError{message: error_message, __exception__: true}

      assert_worker_result(ref, task.id, result, :error)
    end

    test "store result is set but type is not map", %{task: task} do
      error_message = "Task returned :i_am_no_map but store_result requires a map"

      dag_content = """
        defmodule StoreResultInvalidReturnDag do
          use Gust.DSL

          task :#{task.name}, store_result: true do
            Process.sleep(100)
            :i_am_no_map
          end
        end
      """

      mod = compile_dag!(dag_content)
      ref = start_worker_and_monitor!(task, mod, %{store_result: true})
      result = %RuntimeError{message: error_message, __exception__: true}

      assert_worker_result(ref, task.id, result, :error)
    end
  end
end
