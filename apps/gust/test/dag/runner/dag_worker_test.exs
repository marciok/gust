defmodule Gust.DAG.Runner.DAGWorkerTest do
  use Gust.DataCase, async: false

  import ExUnit.CaptureLog
  import Gust.FlowsFixtures
  import Mox

  alias Gust.DAG.Run.ErrorReporter.Worker, as: ErrorReporterWorker
  alias Gust.DAG.Runner.{DAGWorker, RunGateway, TaskExecution}
  alias Gust.DAG.TaskWorker
  alias Gust.Flows

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    replace_env(:dag_stage_coordinator, Gust.DAG.StageCoordinator.RetryingTask)
    replace_env(:dag_task_expander, Gust.DAG.TaskExpander.MapOver)
    replace_env(:dag_adapter, elixir: %{runtime: Gust.RuntimeAdapterMock})
    replace_env(:reclaim_run_delay, 99_999_999)

    dag = dag_fixture()
    run = run_fixture(%{dag_id: dag.id, claim_token: Ecto.UUID.generate()})

    Gust.RuntimeAdapterMock
    |> expect(:setup, fn dag_def, _runtime_id -> dag_def end)

    %{run: run}
  end

  test "owns the active stage and starts task workers directly", %{run: run} do
    dag_def = definition([["first", "second"]])
    expect_task_starts(2)

    Gust.PubSub.subscribe_run(run.id)
    runner = start_runner(run, dag_def)

    assert_receive {:task_started, %Flows.Task{name: "first"}, ^runner}
    assert_receive {:task_started, %Flows.Task{name: "second"}, ^runner}

    assert {:error, :cannot_restart_task_group_on_active_run} =
             RunGateway.call(run, {:restart_task_group, "first"})

    assert {:error, :task_not_found} = RunGateway.call(run, {:restart_mapped_task, -1})
    assert Process.alive?(runner)
    assert_receive {:dag, :run_status, %{run_id: run_id, status: :running}}
    assert run_id == run.id

    assert %Flows.Task{status: :running} = Flows.get_task_by_name("first", run.id, nil)
    assert %Flows.Task{status: :running} = Flows.get_task_by_name("second", run.id, nil)
    assert Process.alive?(runner)
  end

  test "advances stages and completes the run from task results", %{run: run} do
    dag_def =
      definition(
        [["first"], ["second"]],
        %{
          "first" => task_options(store_result: true),
          "second" => task_options()
        }
      )

    expect_task_starts(2)

    Gust.RuntimeAdapterMock
    |> expect(:teardown, fn ^dag_def, _runtime_id -> :ok end)

    Gust.PubSub.subscribe_run(run.id)
    runner = start_runner(run, dag_def)
    ref = Process.monitor(runner)

    assert_receive {:task_started, %Flows.Task{name: "first"} = first, ^runner}
    send(runner, {:task_result, %{"value" => 1}, first.id, :ok})

    assert_receive {:task_started, %Flows.Task{name: "second"} = second, ^runner}
    assert Flows.get_task!(first.id).result == %{"value" => 1}

    send(runner, {:task_result, %{}, second.id, :ok})

    assert_receive {:dag, :run_status, %{run_id: run_id, status: :succeeded}}
    assert run_id == run.id
    assert_receive {:DOWN, ^ref, :process, ^runner, :normal}
    assert Flows.get_run!(run.id).status == :succeeded
  end

  test "restarts a failed mapped instance while its sibling keeps running", %{run: run} do
    task_fixture(%{
      run_id: run.id,
      name: "source",
      status: :succeeded,
      result: %{"gust_task_items" => [%{"item" => "a"}, %{"item" => "b"}]}
    })

    dag_def =
      definition(
        [["mapped"]],
        %{"mapped" => task_options(upstream: ["source"], map_over: :source)}
      )

    expect_task_starts(3)

    Gust.RuntimeAdapterMock
    |> expect(:teardown, fn ^dag_def, _runtime_id -> :ok end)

    Gust.PubSub.subscribe_run(run.id)
    runner = start_runner(run, dag_def)
    ref = Process.monitor(runner)

    assert_receive {:task_started, %Flows.Task{map_index: 0} = first, ^runner}
    assert_receive {:task_started, %Flows.Task{map_index: 1} = sibling, ^runner}

    send(
      runner,
      {:task_result, RuntimeError.exception("failed"), first.id, :non_recoverable_error}
    )

    assert_task_status(first.id, :failed)
    assert Process.alive?(runner)

    failed_task = Flows.get_task!(first.id)

    assert {:ok, %Flows.Task{status: :running, id: restarted_id}} =
             RunGateway.call(run, {:restart_mapped_task, failed_task.id})

    assert restarted_id == first.id
    assert_receive {:task_started, %Flows.Task{id: ^restarted_id, map_index: 0}, ^runner}
    assert Flows.get_task!(restarted_id).error == %{}
    assert Flows.get_task!(restarted_id).attempt == 1

    send(runner, {:task_result, %{}, sibling.id, :ok})
    assert_task_status(sibling.id, :succeeded)
    refute_receive {:DOWN, ^ref, :process, ^runner, _reason}, 100
    assert Flows.get_run!(run.id).status == :running

    send(runner, {:task_result, %{}, restarted_id, :ok})

    assert_receive {:DOWN, ^ref, :process, ^runner, :normal}
    assert Flows.get_run!(run.id).status == :succeeded
    assert Flows.get_task!(restarted_id).status == :succeeded
  end

  test "does not start a duplicate of an already running mapped instance", %{run: run} do
    task_fixture(%{
      run_id: run.id,
      name: "source",
      status: :succeeded,
      result: %{"gust_task_items" => ["a", "b"]}
    })

    dag_def =
      definition(
        [["mapped"]],
        %{"mapped" => task_options(upstream: ["source"], map_over: :source)}
      )

    expect_task_starts(2)
    runner = start_runner(run, dag_def)

    assert_receive {:task_started, %Flows.Task{map_index: 0} = first, ^runner}
    assert_receive {:task_started, %Flows.Task{map_index: 1}, ^runner}

    assert {:error, :task_not_restartable} =
             RunGateway.call(run, {:restart_mapped_task, first.id})
  end

  test "uses all mapped outcomes instead of the last task result", %{run: run} do
    task_fixture(%{
      run_id: run.id,
      name: "source",
      status: :succeeded,
      result: %{"gust_task_items" => ["a", "b"]}
    })

    dag_def =
      definition(
        [["mapped"]],
        %{"mapped" => task_options(upstream: ["source"], map_over: :source)}
      )

    expect_task_starts(2)

    Gust.RuntimeAdapterMock
    |> expect(:teardown, fn ^dag_def, _runtime_id -> :ok end)

    Gust.PubSub.subscribe_run(run.id)
    runner = start_runner(run, dag_def)
    ref = Process.monitor(runner)

    assert_receive {:task_started, %Flows.Task{map_index: 0} = failed, ^runner}
    assert_receive {:task_started, %Flows.Task{map_index: 1} = succeeded, ^runner}

    send(
      runner,
      {:task_result, RuntimeError.exception("failed"), failed.id, :non_recoverable_error}
    )

    assert_task_status(failed.id, :failed)
    send(runner, {:task_result, %{}, succeeded.id, :ok})

    assert_receive {:DOWN, ^ref, :process, ^runner, :normal}
    assert Flows.get_run!(run.id).status == :failed
  end

  test "cancels a running task through the run gateway", %{run: run} do
    dag_def = definition([["running"]])
    expect_task_starts(1)

    Gust.RuntimeAdapterMock
    |> expect(:kill, fn task_pid ->
      assert Process.alive?(task_pid)
      :ok
    end)
    |> expect(:teardown, fn ^dag_def, _runtime_id -> :ok end)

    Gust.PubSub.subscribe_run(run.id)
    runner = start_runner(run, dag_def)
    ref = Process.monitor(runner)

    assert_receive {:task_started, %Flows.Task{name: "running"} = task, ^runner}

    assert {:ok, %Flows.Task{id: task_id, status: :running}} =
             RunGateway.call(run, {:cancel_task, task.id})

    assert task_id == task.id
    assert_task_status(task.id, :failed)
    assert_receive {:DOWN, ^ref, :process, ^runner, :normal}
    assert Flows.get_run!(run.id).status == :failed
  end

  test "stops active task workers, ignores missing tasks, and tears down", %{run: run} do
    dag_def = definition([["running"]])
    expect_task_starts(1)

    Gust.RuntimeAdapterMock
    |> expect(:kill, fn task_pid ->
      Process.exit(task_pid, :kill)
      :ok
    end)
    |> expect(:teardown, fn ^dag_def, _runtime_id -> :ok end)

    runner = start_runner(run, dag_def)
    runner_ref = Process.monitor(runner)

    assert_receive {:task_started, %Flows.Task{name: "running"} = task, ^runner}
    [{task_pid, _value}] = Registry.lookup(Gust.Registry, TaskWorker.registry_name(task))
    task_ref = Process.monitor(task_pid)

    :sys.replace_state(runner, fn state ->
      %{state | current_task_ids: MapSet.put(state.current_task_ids, -1)}
    end)

    assert is_nil(Flows.get_task(-1))

    assert {:ok, %Flows.Run{id: run_id}} = RunGateway.call(run, :stop)
    assert run_id == run.id
    assert_receive {:DOWN, ^task_ref, :process, ^task_pid, :killed}
    assert_receive {:DOWN, ^runner_ref, :process, ^runner, :normal}
  end

  test "returns the task cancellation error and keeps the run alive", %{run: run} do
    dag_def = definition([["running"]])
    expect_task_starts(1)

    Gust.RuntimeAdapterMock
    |> expect(:kill, fn _task_pid -> {:error, :cannot_kill_task} end)

    runner = start_runner(run, dag_def)
    runner_ref = Process.monitor(runner)

    assert_receive {:task_started, %Flows.Task{name: "running"}, ^runner}
    assert {:error, :cannot_kill_task} = RunGateway.call(run, :stop)
    assert Process.alive?(runner)
    refute_receive {:DOWN, ^runner_ref, :process, ^runner, _reason}
  end

  test "persists waiting state and pauses the run", %{run: run} do
    dag_def =
      definition(
        [["approval"]],
        %{"approval" => task_options(wait_for: "approved")}
      )

    Gust.RuntimeAdapterMock
    |> expect(:teardown, fn ^dag_def, _runtime_id -> :ok end)

    Gust.PubSub.subscribe_run(run.id)
    runner = start_runner(run, dag_def)
    ref = Process.monitor(runner)

    assert_receive {:dag, :run_status, %{run_id: run_id, status: :waiting}}
    assert run_id == run.id
    assert_receive {:DOWN, ^ref, :process, ^runner, :normal}

    assert %Flows.Task{status: :waiting, waiting_for: "approved"} =
             Flows.get_task_by_name("approval", run.id, nil)

    assert Flows.get_run!(run.id).status == :waiting
  end

  test "reports a task failure before pausing for another waiting task", %{run: run} do
    dag_def =
      definition(
        [["failure", "approval"]],
        %{
          "failure" => task_options(),
          "approval" => task_options(wait_for: "approved")
        }
      )

    expect_task_starts(1)

    error = RuntimeError.exception("failed")
    test_pid = self()

    Gust.DAGErrorReporterMock
    |> expect(:capture, fn exception, [], data ->
      send(test_pid, {:capture_attempted, exception, data})
      :ok
    end)

    Gust.RuntimeAdapterMock
    |> expect(:teardown, fn ^dag_def, _runtime_id -> :ok end)

    error_reporter_worker = Process.whereis(ErrorReporterWorker)
    previous_reporter_state = :sys.get_state(error_reporter_worker)

    :sys.replace_state(error_reporter_worker, fn _state ->
      %{reporter: Gust.DAGErrorReporterMock}
    end)

    on_exit(fn ->
      :sys.replace_state(error_reporter_worker, fn _state -> previous_reporter_state end)
    end)

    runner = start_runner(run, dag_def)
    allow(Gust.DAGErrorReporterMock, self(), error_reporter_worker)
    ref = Process.monitor(runner)

    assert_receive {:task_started, %Flows.Task{name: "failure"} = task, ^runner}

    capture_log(fn ->
      send(runner, {:task_result, error, task.id, :non_recoverable_error})

      assert_receive {:DOWN, ^ref, :process, ^runner, :normal}
      assert_receive {:capture_attempted, exception, data}
      assert Exception.message(exception) == "RuntimeError\n message: failed"
      assert data.dag_name == dag_def.name

      assert :sys.get_state(ErrorReporterWorker) == %{
               reporter: Gust.DAGErrorReporterMock
             }
    end)

    assert Flows.get_task!(task.id).status == :failed
    assert Flows.get_run!(run.id).status == :waiting
  end

  test "owns retry timers and restarts the task worker", %{run: run} do
    dag_def = definition([["flaky"]])
    expect_task_starts(2)

    Gust.DAGTaskDelayerMock
    |> expect(:calc_delay, fn 1 -> 0 end)

    Gust.RuntimeAdapterMock
    |> expect(:teardown, fn ^dag_def, _runtime_id -> :ok end)

    runner = start_runner(run, dag_def)
    ref = Process.monitor(runner)

    assert_receive {:task_started, %Flows.Task{name: "flaky"} = task, ^runner}
    send(runner, {:task_result, RuntimeError.exception("temporary"), task.id, :error})

    assert_receive {:task_started, %Flows.Task{id: task_id, attempt: 2}, ^runner}
    assert task_id == task.id
    send(runner, {:task_result, %{}, task.id, :ok})

    assert_receive {:DOWN, ^ref, :process, ^runner, :normal}
    assert Flows.get_task!(task.id).status == :succeeded
    assert Flows.get_task!(task.id).attempt == 2
  end

  test "fails the run when an initial task worker cannot start", %{run: run} do
    dag_def = definition([["blocked"]])
    expect_task_start_outcomes([{:error, :max_children}])

    Gust.RuntimeAdapterMock
    |> expect(:teardown, fn ^dag_def, _runtime_id -> :ok end)

    runner = start_runner(run, dag_def)
    ref = Process.monitor(runner)

    assert_receive {:DOWN, ^ref, :process, ^runner, :normal}

    assert %Flows.Task{
             status: :failed,
             error: %{
               "type" => "RuntimeError",
               "message" => "Task worker could not start: :max_children"
             }
           } = Flows.get_task_by_name("blocked", run.id, nil)

    assert Flows.get_run!(run.id).status == :failed
  end

  test "fails the task when its retry worker cannot start", %{run: run} do
    dag_def = definition([["flaky"]])
    expect_task_start_outcomes([:ok, {:error, :max_children}])

    Gust.DAGTaskDelayerMock
    |> expect(:calc_delay, fn 1 -> 0 end)

    Gust.RuntimeAdapterMock
    |> expect(:teardown, fn ^dag_def, _runtime_id -> :ok end)

    runner = start_runner(run, dag_def)
    ref = Process.monitor(runner)

    assert_receive {:task_started, %Flows.Task{name: "flaky"} = task, ^runner}
    send(runner, {:task_result, RuntimeError.exception("temporary"), task.id, :error})

    assert_receive {:DOWN, ^ref, :process, ^runner, :normal}

    assert %Flows.Task{
             status: :failed,
             attempt: 2,
             error: %{"message" => "Task worker could not start: :max_children"}
           } = Flows.get_task!(task.id)
  end

  test "keeps a failed mapped task terminal when its manual restart cannot start", %{run: run} do
    task_fixture(%{
      run_id: run.id,
      name: "source",
      status: :succeeded,
      result: %{"gust_task_items" => ["a", "b"]}
    })

    dag_def =
      definition(
        [["mapped"]],
        %{"mapped" => task_options(upstream: ["source"], map_over: :source)}
      )

    expect_task_start_outcomes([:ok, :ok, {:error, :max_children}])

    Gust.PubSub.subscribe_run(run.id)
    runner = start_runner(run, dag_def)

    assert_receive {:task_started, %Flows.Task{map_index: 0} = failed, ^runner}
    assert_receive {:task_started, %Flows.Task{map_index: 1}, ^runner}

    send(
      runner,
      {:task_result, RuntimeError.exception("failed"), failed.id, :non_recoverable_error}
    )

    assert_task_status(failed.id, :failed)

    assert {:error, :max_children} =
             RunGateway.call(run, {:restart_mapped_task, failed.id})

    assert %Flows.Task{
             status: :failed,
             error: %{"message" => "Task worker could not start: :max_children"}
           } = Flows.get_task!(failed.id)

    assert Process.alive?(runner)
  end

  test "cancels a pending retry through the run gateway", %{run: run} do
    dag_def = definition([["flaky"]])
    expect_task_starts(1)

    Gust.DAGTaskDelayerMock
    |> expect(:calc_delay, fn 1 -> 60_000 end)

    Gust.RuntimeAdapterMock
    |> expect(:teardown, fn ^dag_def, _runtime_id -> :ok end)

    runner = start_runner(run, dag_def)
    ref = Process.monitor(runner)

    assert_receive {:task_started, %Flows.Task{name: "flaky"} = task, ^runner}

    send(runner, {:task_result, RuntimeError.exception("temporary"), task.id, :error})
    state = :sys.get_state(runner)
    assert %{restart_timer: timer} = state.coord.retrying[task.id]
    assert is_reference(timer)

    assert {:ok, %Flows.Task{id: task_id, status: :retrying}} =
             RunGateway.call(run, {:cancel_task, task.id})

    assert task_id == task.id

    assert_receive {:DOWN, ^ref, :process, ^runner, :normal}
    assert Flows.get_task!(task.id).status == :failed
    assert Flows.get_run!(run.id).status == :failed
  end

  test "returns cancellation errors without changing active execution", %{run: run} do
    dag_def = definition([["active"]])
    expect_task_starts(1)

    runner = start_runner(run, dag_def)
    assert_receive {:task_started, %Flows.Task{name: "active"} = task, ^runner}

    other_task = task_fixture(%{run_id: run.id, name: "other", status: :running})

    assert {:error, :task_not_found} =
             RunGateway.call(run, {:cancel_task, -1})

    assert {:error, :task_not_on_current_stage} =
             RunGateway.call(run, {:cancel_task, other_task.id})

    {:ok, _task} = Flows.update_task_status(task, :succeeded)

    assert {:error, :task_not_cancellable} =
             RunGateway.call(run, {:cancel_task, task.id})

    assert Process.alive?(runner)
  end

  test "reports a missing retry timer instead of accepting a stale cancellation", %{run: run} do
    dag_def = definition([["active"]])
    expect_task_starts(1)

    runner = start_runner(run, dag_def)
    assert_receive {:task_started, %Flows.Task{name: "active"} = task, ^runner}
    {:ok, _task} = Flows.update_task_status(task, :retrying)

    assert {:error, :retry_timer_not_found} =
             RunGateway.call(run, {:cancel_task, task.id})

    assert Process.alive?(runner)
  end

  test "renews its run lease and retains the renewed run", %{run: run} do
    dag_def = definition([["active"]])
    expect_task_starts(1)

    renewed_run = %{
      run
      | status: :running,
        claim_expires_at: DateTime.add(DateTime.utc_now(), 60)
    }

    Gust.RunClaimMock
    |> expect(:renew_run, fn run_id, token ->
      assert run_id == run.id
      assert token == run.claim_token
      renewed_run
    end)

    Gust.RuntimeAdapterMock
    |> expect(:teardown, fn ^dag_def, _runtime_id -> :ok end)

    runner = start_runner(run, dag_def)
    ref = Process.monitor(runner)

    assert_receive {:task_started, task, ^runner}
    send(runner, {:renew_claim, run.claim_token})

    assert %{run: ^renewed_run} = :sys.get_state(runner)

    send(runner, {:task_result, %{}, task.id, :ok})
    assert_receive {:DOWN, ^ref, :process, ^runner, :normal}
  end

  test "stops and tears down its runtime when the run lease is lost", %{run: run} do
    dag_def = definition([["active"]])
    expect_task_starts(1)

    Gust.RunClaimMock
    |> expect(:renew_run, fn run_id, token ->
      assert run_id == run.id
      assert token == run.claim_token
      nil
    end)

    Gust.RuntimeAdapterMock
    |> expect(:teardown, fn ^dag_def, _runtime_id -> :ok end)

    runner = start_runner(run, dag_def)
    ref = Process.monitor(runner)

    assert_receive {:task_started, _task, ^runner}
    send(runner, {:renew_claim, run.claim_token})

    assert_receive {:DOWN, ^ref, :process, ^runner, :normal}
  end

  test "pauses after active work finishes when another task is waiting", %{run: run} do
    dag_def =
      definition(
        [["work", "approval"]],
        %{
          "work" => task_options(),
          "approval" => task_options(wait_for: "approved")
        }
      )

    expect_task_starts(1)

    Gust.RuntimeAdapterMock
    |> expect(:teardown, fn ^dag_def, _runtime_id -> :ok end)

    runner = start_runner(run, dag_def)
    ref = Process.monitor(runner)

    assert_receive {:task_started, %Flows.Task{name: "work"} = work, ^runner}
    _state = :sys.get_state(runner)

    assert %Flows.Task{status: :waiting} =
             Flows.get_task_by_name("approval", run.id, nil)

    assert Process.alive?(runner)
    send(runner, {:task_result, %{}, work.id, :ok})

    assert_receive {:DOWN, ^ref, :process, ^runner, :normal}
    assert Flows.get_task!(work.id).status == :succeeded
    assert Flows.get_run!(run.id).status == :waiting
  end

  test "cancels a waiting task while another task remains active", %{run: run} do
    dag_def =
      definition(
        [["work", "approval"]],
        %{
          "work" => task_options(),
          "approval" => task_options(wait_for: "approved")
        }
      )

    expect_task_starts(1)

    Gust.RuntimeAdapterMock
    |> expect(:teardown, fn ^dag_def, _runtime_id -> :ok end)

    Gust.PubSub.subscribe_run(run.id)
    runner = start_runner(run, dag_def)
    ref = Process.monitor(runner)

    assert_receive {:task_started, %Flows.Task{name: "work"} = work, ^runner}
    _state = :sys.get_state(runner)
    waiting = Flows.get_task_by_name("approval", run.id, nil)

    assert {:ok, %Flows.Task{id: waiting_id, status: :waiting}} =
             RunGateway.call(run, {:cancel_task, waiting.id})

    assert waiting_id == waiting.id
    assert_task_status(waiting.id, :failed)

    assert %{coord: %{waiting: waiting_ids}} = :sys.get_state(runner)
    refute MapSet.member?(waiting_ids, waiting.id)
    assert Flows.get_task!(waiting.id).waiting_for == nil

    send(runner, {:task_result, %{}, work.id, :ok})

    assert_receive {:DOWN, ^ref, :process, ^runner, :normal}
    assert Flows.get_run!(run.id).status == :failed
  end

  test "finishes a stage from a task that was already processed", %{run: run} do
    task = task_fixture(%{run_id: run.id, name: "done", status: :succeeded})
    dag_def = definition([["done"]])

    Gust.RuntimeAdapterMock
    |> expect(:teardown, fn ^dag_def, _runtime_id -> :ok end)

    runner = start_runner(run, dag_def)
    ref = Process.monitor(runner)

    assert_receive {:DOWN, ^ref, :process, ^runner, :normal}
    assert Flows.get_task!(task.id).status == :succeeded
    assert Flows.get_run!(run.id).status == :succeeded
  end

  test "fails a stage when mapped task parameters cannot be loaded", %{run: run} do
    dag_def =
      definition(
        [["mapped"]],
        %{"mapped" => task_options(upstream: ["missing"], map_over: :missing)}
      )

    Gust.RuntimeAdapterMock
    |> expect(:teardown, fn ^dag_def, _runtime_id -> :ok end)

    runner = start_runner(run, dag_def)
    ref = Process.monitor(runner)

    assert_receive {:DOWN, ^ref, :process, ^runner, :normal}

    assert %Flows.Task{
             status: :failed,
             error: %{"message" => "Task: missing not found on run: " <> run_id}
           } = Flows.get_task_by_name("mapped", run.id, nil)

    assert run_id == to_string(run.id)
    assert Flows.get_run!(run.id).status == :failed
  end

  test "runs the finished callback after the final stage", %{run: run} do
    dag_def = %{definition([["only"]]) | options: [on_finished_callback: :finished]}
    expect_task_starts(1)

    Gust.RuntimeAdapterMock
    |> expect(:on_finished_callback, fn ^dag_def, :finished, callback_run, :ok ->
      assert callback_run.id == run.id
      :ok
    end)
    |> expect(:teardown, fn ^dag_def, _runtime_id -> :ok end)

    runner = start_runner(run, dag_def)
    ref = Process.monitor(runner)

    assert_receive {:task_started, task, ^runner}
    send(runner, {:task_result, %{}, task.id, :ok})

    assert_receive {:DOWN, ^ref, :process, ^runner, :normal}
  end

  defp start_runner(run, dag_def) do
    start_supervised!({DAGWorker, %{run: run, dag_def: dag_def}})
  end

  defp expect_task_starts(count) do
    test_pid = self()

    Gust.DAGTaskRunnerSupervisorMock
    |> expect(:start_child, count, fn task, _dag_def, owner_pid, _opts ->
      task = TaskExecution.update_status!(task, :running)
      worker = start_mock_task_worker(task)
      send(test_pid, {:task_started, task, owner_pid})
      {:ok, worker}
    end)
  end

  defp expect_task_start_outcomes(outcomes) do
    {:ok, remaining} = Agent.start_link(fn -> outcomes end)
    test_pid = self()

    Gust.DAGTaskRunnerSupervisorMock
    |> expect(:start_child, length(outcomes), fn task, _dag_def, owner_pid, _opts ->
      outcome = Agent.get_and_update(remaining, fn [outcome | rest] -> {outcome, rest} end)

      case outcome do
        :ok ->
          task = TaskExecution.update_status!(task, :running)
          worker = start_mock_task_worker(task)
          send(test_pid, {:task_started, task, owner_pid})
          {:ok, worker}

        {:error, reason} ->
          {:error, reason}
      end
    end)
  end

  defp start_mock_task_worker(task) do
    owner = self()
    registry_name = TaskWorker.registry_name(task)

    case Registry.lookup(Gust.Registry, registry_name) do
      [{existing_worker, _value}] ->
        ref = Process.monitor(existing_worker)
        Process.exit(existing_worker, :kill)

        receive do
          {:DOWN, ^ref, :process, ^existing_worker, :killed} -> :ok
        end

      [] ->
        :ok
    end

    worker =
      spawn(fn ->
        {:ok, _owner} = Registry.register(Gust.Registry, registry_name, nil)
        send(owner, {:mock_task_worker_registered, self()})
        Process.sleep(5_000)
      end)

    receive do
      {:mock_task_worker_registered, ^worker} -> worker
    end
  end

  defp assert_task_status(task_id, status) do
    assert_receive {:dag, :run_status, %{task_id: ^task_id, status: ^status}}

    assert Flows.get_task!(task_id).status == status
  end

  defp definition(stages, tasks \\ nil) do
    task_names = stages |> List.flatten() |> Enum.uniq()
    tasks = tasks || Map.new(task_names, &{&1, task_options()})

    %Gust.DAG.Definition{
      mod: TestDag,
      stages: stages,
      tasks: tasks
    }
  end

  defp task_options(opts \\ []) do
    %{
      upstream: opts |> Keyword.get(:upstream, []) |> MapSet.new(),
      store_result: Keyword.get(opts, :store_result, false),
      map_over: Keyword.get(opts, :map_over),
      wait_for: Keyword.get(opts, :wait_for),
      skip_if: nil
    }
  end
end
