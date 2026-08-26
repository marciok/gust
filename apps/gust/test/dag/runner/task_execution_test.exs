defmodule Gust.DAG.Runner.TaskExecutionTest do
  use Gust.DataCase, async: true

  import Gust.FlowsFixtures
  import Mox

  alias Gust.DAG.Definition
  alias Gust.DAG.Runner.TaskExecution
  alias Gust.DAG.TaskWorker
  alias Gust.Flows

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    dag = dag_fixture()
    run = run_fixture(%{dag_id: dag.id})
    task = task_fixture(%{run_id: run.id, name: "task"})

    %{run: run, task: task}
  end

  test "starts a task worker with its definition options and reloads the task", %{task: task} do
    {:ok, task} =
      Flows.update_task_wait_state(task, %{
        waiting_for: "approval",
        wait_satisfied_at: DateTime.utc_now()
      })

    owner_pid = self()
    task_opts = %{store_result: false}
    dag_def = definition(task.name, task_opts)
    task_id = task.id

    Gust.DAGTaskRunnerSupervisorMock
    |> expect(:start_child, fn %Flows.Task{
                                 id: ^task_id,
                                 waiting_for: nil,
                                 wait_satisfied_at: nil
                               } = cleared_task,
                               ^dag_def,
                               ^owner_pid,
                               ^task_opts ->
      {:ok, _task} = Flows.update_task_status(cleared_task, :running)
      {:ok, self()}
    end)

    assert {:ok, %Flows.Task{id: task_id, status: :running}} =
             TaskExecution.start(task, dag_def, owner_pid)

    assert task_id == task.id
  end

  test "returns a task worker startup error", %{task: task} do
    dag_def = definition(task.name)

    Gust.DAGTaskRunnerSupervisorMock
    |> expect(:start_child, fn ^task, ^dag_def, _owner_pid, _task_opts ->
      {:error, :max_children}
    end)

    assert {:error, :max_children} = TaskExecution.start(task, dag_def, self())
  end

  test "kills the locally registered task worker", %{task: task} do
    parent = self()

    worker =
      spawn(fn ->
        {:ok, _owner} = Registry.register(Gust.Registry, TaskWorker.registry_name(task), nil)
        send(parent, {:registered, self()})
        Process.sleep(:infinity)
      end)

    assert_receive {:registered, ^worker}
    ref = Process.monitor(worker)

    assert :ok = TaskExecution.cancel(task, definition(task.name))
    assert_receive {:DOWN, ^ref, :process, ^worker, :killed}
  end

  test "returns an error when the task worker is not registered", %{task: task} do
    assert {:error, :task_worker_not_found} =
             TaskExecution.cancel(task, definition(task.name))
  end

  test "stores successful results and clears the previous error", %{task: task} do
    previous_error = %{"message" => "old error"}
    {:ok, task} = Flows.update_task_error(task, previous_error)
    result = %{"value" => 42}
    dag_def = definition(task.name, %{store_result: true})

    assert %Flows.Task{result: ^result, error: %{}} =
             TaskExecution.apply_result(dag_def, task.id, :ok, result)

    assert %Flows.Task{result: ^result, error: %{}} = Flows.get_task!(task.id)
  end

  test "does not replace the result when result storage is disabled", %{task: task} do
    previous_result = %{"value" => "keep"}

    {:ok, task} =
      Flows.update_task_result_error(task, previous_result, %{"message" => "clear"})

    dag_def = definition(task.name, %{store_result: false})

    assert %Flows.Task{result: ^previous_result, error: %{}} =
             TaskExecution.apply_result(dag_def, task.id, :ok, %{"value" => "ignore"})

    assert %Flows.Task{result: ^previous_result, error: %{}} = Flows.get_task!(task.id)
  end

  test "parses and persists task errors", %{task: task} do
    dag_def = definition(task.name)

    assert %Flows.Task{error: %{type: "RuntimeError", message: "boom"}} =
             TaskExecution.apply_result(
               dag_def,
               task.id,
               :non_recoverable_error,
               RuntimeError.exception("boom")
             )

    assert %Flows.Task{error: %{"type" => "RuntimeError", "message" => "boom"}} =
             Flows.get_task!(task.id)
  end

  test "maps execution outcomes to persisted terminal statuses", %{run: run, task: task} do
    cases = [
      {:ok, :succeeded},
      {:error, :failed},
      {:non_recoverable_error, :failed},
      {:upstream_failed, :upstream_failed},
      {:skipped, :skipped},
      {:cancelled, :failed}
    ]

    Enum.with_index(cases, fn {outcome, expected_status}, index ->
      current_task =
        if index == 0 do
          task
        else
          task_fixture(%{run_id: run.id, name: "task_#{index}"})
        end

      assert %Flows.Task{status: ^expected_status} = TaskExecution.finish(current_task, outcome)
      assert Flows.get_task!(current_task.id).status == expected_status
    end)

    assert TaskExecution.finish(task, :already_processed) == nil
  end

  test "updates status, broadcasts it, and returns the task directly", %{run: run, task: task} do
    Gust.PubSub.subscribe_run(run.id)

    assert %Flows.Task{id: task_id, status: :running} =
             TaskExecution.update_status!(task, :running)

    assert task_id == task.id

    assert_receive {:dag, :run_status, %{run_id: run_id, task_id: ^task_id, status: :running}}

    assert run_id == run.id
  end

  test "raises when status persistence fails", %{task: task} do
    assert_raise MatchError, fn -> TaskExecution.update_status!(task, :not_a_status) end
  end

  test "marks a task failed when its worker cannot start", %{task: task} do
    assert {:error, :max_children} = TaskExecution.fail_start(task, :max_children)

    assert %Flows.Task{
             status: :failed,
             error: %{
               "type" => "RuntimeError",
               "message" => "Task worker could not start: :max_children"
             }
           } = Flows.get_task!(task.id)
  end

  test "aggregates terminal task statuses by precedence", %{run: run} do
    cases = [
      {[:succeeded, :succeeded], :ok},
      {[:succeeded, :failed], :error},
      {[:skipped, :upstream_failed], :upstream_failed},
      {[:skipped, :skipped], :skipped},
      {[:skipped, :succeeded], :ok},
      {[], :ok}
    ]

    Enum.with_index(cases, fn {statuses, expected}, case_index ->
      task_ids =
        Enum.with_index(statuses, fn status, task_index ->
          task =
            task_fixture(%{
              run_id: run.id,
              name: "aggregate_#{case_index}_#{task_index}",
              status: status
            })

          task.id
        end)

      assert TaskExecution.aggregate_status(task_ids) == expected
    end)
  end

  test "loads all task statuses in one query", %{run: run} do
    task_ids =
      Enum.map(1..3, fn index ->
        task_fixture(%{
          run_id: run.id,
          name: "bulk_status_#{index}",
          status: :succeeded
        }).id
      end)

    handler_id = {__MODULE__, self(), make_ref()}
    caller = self()

    :ok =
      :telemetry.attach(
        handler_id,
        [:gust, :repo, :query],
        fn _event, _measurements, _metadata, {test_pid, query_caller} ->
          if self() == query_caller, do: send(test_pid, :task_status_query)
        end,
        {self(), caller}
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    assert TaskExecution.aggregate_status(task_ids) == :ok
    assert_receive :task_status_query
    refute_receive :task_status_query, 20
  end

  defp definition(task_name, task_opts \\ %{store_result: false}) do
    %Definition{adapter: :elixir, tasks: %{task_name => task_opts}}
  end
end
