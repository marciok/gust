defmodule Gust.DAG.Runner.ErrorReporterTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Mox

  alias Gust.DAG.Run.ErrorReporter.Worker
  alias Gust.DAG.Runner.{TaskExecution, TaskFailureError}

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    worker = Process.whereis(Worker)
    previous_state = :sys.get_state(worker)

    :sys.replace_state(worker, fn _state -> %{reporter: Gust.DAGErrorReporterMock} end)
    allow(Gust.DAGErrorReporterMock, self(), worker)

    on_exit(fn -> :sys.replace_state(worker, fn _state -> previous_state end) end)

    %{task: %{name: "example_task", run_id: 42}, worker: worker}
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
    assert data == %{task_name: "example_task", run_id: 42, dag_name: "example_dag"}
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
    error = Gust.DAG.NonRecError.exception("stop")

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

  test "contains reporter exceptions", %{task: task, worker: worker} do
    log = capture_reporter_failure(task, worker, fn -> raise "reporter unavailable" end)
    assert log =~ "Error reporter Gust.DAGErrorReporterMock failed"
    assert log =~ "reporter unavailable"
  end

  test "contains reporter throws", %{task: task, worker: worker} do
    log = capture_reporter_failure(task, worker, fn -> throw(:reporter_unavailable) end)

    assert log =~ "Error reporter Gust.DAGErrorReporterMock failed"
    assert log =~ "** (throw) :reporter_unavailable"
  end

  test "contains reporter exits", %{task: task, worker: worker} do
    log = capture_reporter_failure(task, worker, fn -> exit(:reporter_unavailable) end)

    assert log =~ "Error reporter Gust.DAGErrorReporterMock failed"
    assert log =~ "** (exit) :reporter_unavailable"
  end

  defp capture_reporter_failure(task, worker, failure) do
    test_pid = self()

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
      assert :sys.get_state(worker) == %{reporter: Gust.DAGErrorReporterMock}
    end)
  end
end
