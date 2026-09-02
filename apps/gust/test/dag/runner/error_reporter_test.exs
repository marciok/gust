defmodule Gust.DAG.Runner.ErrorReporterTest do
  use Gust.DataCase, async: false

  import ExUnit.CaptureLog
  import Gust.FlowsFixtures
  import Mox

  alias Gust.DAG.NonRecError
  alias Gust.DAG.Run.ErrorReporter.Worker
  alias Gust.DAG.Runner.{TaskExecution, TaskFailureError}
  alias Gust.Flows

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    worker = Process.whereis(Worker)
    previous_state = :sys.get_state(worker)

    :sys.replace_state(worker, fn _state -> %{reporter: Gust.DAGErrorReporterMock} end)
    allow(Gust.DAGErrorReporterMock, self(), worker)

    on_exit(fn ->
      case Process.whereis(Worker) do
        pid when is_pid(pid) -> :sys.replace_state(pid, fn _state -> previous_state end)
        _other -> :ok
      end
    end)

    %{
      task: %{id: 7, attempt: 1, name: "example_task", run_id: 42},
      worker: worker
    }
  end

  test "reports retryable errors with their stacktrace and task metadata", %{task: task} do
    test_pid = self()
    error = RuntimeError.exception("boom")
    stacktrace = [{__MODULE__, :example, 0, [file: ~c"example.ex", line: 10]}]

    expect(Gust.DAGErrorReporterMock, :capture, fn exception, stacktrace, data ->
      send(test_pid, {:captured, exception, stacktrace, data})
      :ok
    end)

    assert :ok =
             TaskExecution.maybe_report_error(
               task,
               :error,
               {:error_with_stacktrace, error, stacktrace},
               "example_dag"
             )

    assert_receive {:captured, exception, ^stacktrace, data}
    assert %TaskFailureError{message: "RuntimeError\n message: boom"} = exception

    assert data == %{
             task_id: 7,
             task_name: "example_task",
             run_id: 42,
             dag_name: "example_dag"
           }
  end

  test "reports bare exceptions without assuming they have a message field", %{task: task} do
    test_pid = self()
    error = FunctionClauseError.exception([])

    expect(Gust.DAGErrorReporterMock, :capture, fn exception, stacktrace, _data ->
      send(test_pid, {:captured, exception, stacktrace})
      :ok
    end)

    assert :ok = TaskExecution.maybe_report_error(task, :error, error, "example_dag")

    assert_receive {:captured, exception, []}

    assert %TaskFailureError{
             message: "FunctionClauseError\n message: no function clause matches"
           } = exception
  end

  test "reports non-recoverable errors", %{task: task} do
    test_pid = self()
    error = NonRecError.exception("stop")

    expect(Gust.DAGErrorReporterMock, :capture, fn exception, [], _data ->
      send(test_pid, {:captured, exception})
      :ok
    end)

    assert :ok =
             TaskExecution.maybe_report_error(task, :non_recoverable_error, error, "example_dag")

    assert_receive {:captured, exception}
    assert %TaskFailureError{message: "Gust.DAG.NonRecError\n message: stop"} = exception
  end

  test "does not report non-error outcomes", %{task: task} do
    assert :ok = TaskExecution.maybe_report_error(task, :ok, %{}, "example_dag")
  end

  test "attaches a returned external reference to the failed task error", %{worker: worker} do
    dag = dag_fixture(%{name: "reported_dag"})
    run = run_fixture(%{dag_id: dag.id})

    task =
      task_fixture(%{
        run_id: run.id,
        name: "reported_task",
        status: :failed,
        error: %{"type" => "RuntimeError", "message" => "boom"}
      })

    reference = "https://errors.example.com/events/event-123"

    expect(Gust.DAGErrorReporterMock, :capture, fn _exception, [], data ->
      assert data.task_id == task.id
      {:ok, reference}
    end)

    Gust.PubSub.subscribe_task(task.id)

    assert :ok =
             TaskExecution.maybe_report_error(
               task,
               :non_recoverable_error,
               RuntimeError.exception("boom"),
               dag.name
             )

    assert :sys.get_state(worker) == %{reporter: Gust.DAGErrorReporterMock}
    assert_receive {:task, :updated, %{task_id: task_id}}
    assert task_id == task.id

    assert Flows.get_task!(task.id).error == %{
             "type" => "RuntimeError",
             "message" => "boom",
             "external_reference" => "https://errors.example.com/events/event-123"
           }
  end

  test "ignores a returned reference when the task is no longer failed", %{worker: worker} do
    previous_log_level = Logger.level()
    Logger.configure(level: :debug)
    on_exit(fn -> Logger.configure(level: previous_log_level) end)

    dag = dag_fixture(%{name: "retried_dag"})
    run = run_fixture(%{dag_id: dag.id})

    task =
      task_fixture(%{
        run_id: run.id,
        name: "retried_task",
        status: :running,
        error: %{"type" => "RuntimeError", "message" => "new failure"}
      })

    expect(Gust.DAGErrorReporterMock, :capture, fn _exception, [], _data ->
      {:ok, "https://errors.example.com/events/old-attempt"}
    end)

    Gust.PubSub.subscribe_task(task.id)

    assert :ok =
             TaskExecution.maybe_report_error(
               task,
               :non_recoverable_error,
               RuntimeError.exception("old failure"),
               dag.name
             )

    assert :sys.get_state(worker) == %{reporter: Gust.DAGErrorReporterMock}
    refute_receive {:task, :updated, %{task_id: _task_id}}

    assert Flows.get_task!(task.id).error == %{
             "type" => "RuntimeError",
             "message" => "new failure"
           }
  end

  test "logs and ignores an invalid external reference", %{worker: worker} do
    expect(Gust.DAGErrorReporterMock, :capture, fn _exception, [], _data ->
      {:ok, "javascript:alert(1)"}
    end)

    log =
      capture_log(fn ->
        assert :ok =
                 TaskExecution.maybe_report_error(
                   %{id: 7, name: "example_task", run_id: 42},
                   :non_recoverable_error,
                   RuntimeError.exception("boom"),
                   "example_dag"
                 )

        assert :sys.get_state(worker) == %{reporter: Gust.DAGErrorReporterMock}
      end)

    assert log =~ "Error reporter returned an invalid external reference"
  end

  test "treats a missing task as stale" do
    assert {:error, :stale_task} =
             Flows.attach_task_error_reference(-1, "https://errors.example.com/events/1")
  end

  test "logs and ignores task errors when no reporter is configured", %{worker: worker} do
    :sys.replace_state(worker, fn _state -> %{reporter: nil} end)
    previous_log_level = Logger.level()
    Logger.configure(level: :debug)
    on_exit(fn -> Logger.configure(level: previous_log_level) end)

    log =
      capture_log(fn ->
        assert :ok =
                 Worker.report(
                   RuntimeError.exception("task failed"),
                   [],
                   %{task_name: "example_task", run_id: 42, dag_name: "example_dag"}
                 )

        assert :sys.get_state(worker) == %{reporter: nil}
      end)

    assert log =~ "Task error received but not captured because no error reporter is configured"
  end

  test "crashes the worker on reporter exceptions", %{task: task, worker: worker} do
    log = reporter_failure(task, worker, fn -> raise "reporter unavailable" end)
    assert log =~ "Error reporter Gust.DAGErrorReporterMock failed"
    assert log =~ "reporter unavailable"
  end

  test "crashes the worker on reporter throws", %{task: task, worker: worker} do
    log = reporter_failure(task, worker, fn -> throw(:reporter_unavailable) end)

    assert log =~ "Error reporter Gust.DAGErrorReporterMock failed"
    assert log =~ "** (throw) :reporter_unavailable"
  end

  defp reporter_failure(task, worker, failure) do
    test_pid = self()
    worker_ref = Process.monitor(worker)

    expect(Gust.DAGErrorReporterMock, :capture, fn _exception, [], _data ->
      send(test_pid, :capture_attempted)
      failure.()
    end)

    capture_log(fn ->
      assert :ok =
               TaskExecution.maybe_report_error(
                 task,
                 :non_recoverable_error,
                 RuntimeError.exception("task failed"),
                 "example_dag"
               )

      assert_receive :capture_attempted
      assert_receive {:DOWN, ^worker_ref, :process, ^worker, _reason}
    end)
  end
end
