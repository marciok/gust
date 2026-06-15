defmodule Dag.Runner.StageWorkerTest do
  alias Gust.Flows
  use Gust.DataCase, async: false

  import Gust.FlowsFixtures

  import Mox

  setup :verify_on_exit!
  setup :set_mox_from_context

  defp stage_entry(status, task), do: {status, task}

  defp expect_coord_new(task) do
    task_id = task.id

    Gust.DAGStageCoordinatorMock
    |> expect(:new, fn [^task_id] -> %{} end)
  end

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
    Gust.DAGTaskRunnerSupervisorMock
    |> expect(:start_child, fn _task, %Gust.DAG.Definition{} = incoming_def, _pid, _opts ->
      assert incoming_def.mod == dag_def.mod
      assert incoming_def.adapter == dag_def.adapter
      {:ok, spawn(fn -> Process.sleep(10) end)}
    end)

    expect_coord_new(task)

    :ok
  end

  def upstream_failed(%{task: task}) do
    expect_coord_new(task)

    :ok
  end

  def upstream_skipped(%{task: task}) do
    expect_coord_new(task)

    :ok
  end

  describe "handle_continue/2 when task was already processed" do
    test "does update task result", %{
      run: run,
      dag_def: dag_def,
      task: task
    } do
      prev_result = %{"prev_result" => true}
      {:ok, task} = Flows.update_task_result(task, prev_result)

      expect_coord_new(task)

      Gust.PubSub.subscribe_run(run.id)
      task_id = task.id
      run_id = run.id

      Gust.DAGStageCoordinatorMock
      |> expect(:apply_task_result, fn _coord, _task, :already_processed ->
        {:finished, %{running: %{}}}
      end)

      runner_pid =
        start_link_supervised!(
          {Gust.DAG.Runner.StageWorker,
           %{
             stage: [stage_entry(:already_processed, task)],
             dag_def: dag_def,
             run_id: run.id
           }}
        )

      ref = Process.monitor(runner_pid)

      assert_receive {:stage_completed, :already_processed}, 400

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
          {Gust.DAG.Runner.StageWorker,
           %{stage: [stage_entry(:upstream_failed, task)], dag_def: dag_def}}
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
          {Gust.DAG.Runner.StageWorker,
           %{stage: [stage_entry(:upstream_failed, task)], dag_def: dag_def}}
        )

      ref = Process.monitor(runner_pid)

      assert_receive {:dag, :run_status, %{run_id: ^run_id, status: :upstream_failed}},
                     400

      assert Flows.get_task!(task_id).status == :upstream_failed

      refute_receive {:stage_completed, :upstream_failed}, 400
      refute_receive {:DOWN, ^ref, :process, _pid, :normal}, 400
    end
  end

  describe "handle_continue/2 when upstream was skipped" do
    setup [:upstream_skipped]

    test "marks task skipped and finishes the stage", %{
      run: run,
      dag_def: dag_def,
      task: task
    } do
      Gust.PubSub.subscribe_run(run.id)
      task_id = task.id
      run_id = run.id

      Gust.DAGStageCoordinatorMock
      |> expect(:apply_task_result, fn _coord, _task, :skipped ->
        {:finished, %{running: %{}}}
      end)

      runner_pid =
        start_link_supervised!(
          {Gust.DAG.Runner.StageWorker, %{stage: [stage_entry(:skipped, task)], dag_def: dag_def}}
        )

      ref = Process.monitor(runner_pid)

      assert_receive {:dag, :run_status, %{run_id: ^run_id, status: :skipped}}, 400
      assert Flows.get_task!(task_id).status == :skipped

      assert_receive {:stage_completed, :skipped}, 400
      assert_receive {:DOWN, ^ref, :process, _pid, :normal}, 400
    end

    test "marks task skipped and keeps stage running", %{
      run: run,
      dag_def: dag_def,
      task: task
    } do
      Gust.PubSub.subscribe_run(run.id)
      task_id = task.id
      run_id = run.id

      Gust.DAGStageCoordinatorMock
      |> expect(:apply_task_result, fn _coord, _task, :skipped ->
        {:continue, %{running: %{}}}
      end)

      runner_pid =
        start_link_supervised!(
          {Gust.DAG.Runner.StageWorker, %{stage: [stage_entry(:skipped, task)], dag_def: dag_def}}
        )

      ref = Process.monitor(runner_pid)

      assert_receive {:dag, :run_status, %{run_id: ^run_id, status: :skipped}}, 400
      assert Flows.get_task!(task_id).status == :skipped

      refute_receive {:stage_completed, :skipped}, 400
      refute_receive {:DOWN, ^ref, :process, _pid, :normal}, 400
    end
  end

  describe "handle_continue/2 when task expansion failed" do
    test "persists the error, fails the task, and finishes the stage", %{
      run: run,
      dag_def: dag_def,
      task: task
    } do
      error = %RuntimeError{message: "upstream result cannot be expanded"}
      task_id = task.id
      run_id = run.id

      expect_coord_new(task)
      Gust.PubSub.subscribe_run(run_id)

      Gust.DAGStageCoordinatorMock
      |> expect(:apply_task_result, fn _coord,
                                       %Flows.Task{id: ^task_id},
                                       :non_recoverable_error ->
        {:finished, %{running: %{}}}
      end)

      runner_pid =
        start_link_supervised!(
          {Gust.DAG.Runner.StageWorker,
           %{
             stage: [stage_entry({:non_recoverable_error, error}, task)],
             dag_def: dag_def,
             run_id: run_id
           }}
        )

      ref = Process.monitor(runner_pid)

      assert_receive {:dag, :run_status, %{run_id: ^run_id, status: :failed, task_id: ^task_id}},
                     400

      assert %Flows.Task{
               status: :failed,
               error: %{
                 "type" => "RuntimeError",
                 "message" => "upstream result cannot be expanded"
               }
             } = Flows.get_task!(task_id)

      assert_receive {:stage_completed, :non_recoverable_error}, 400
      assert_receive {:DOWN, ^ref, :process, ^runner_pid, :normal}, 400
    end
  end

  test "starts mapped task entries with params", %{run: run, dag_def: dag_def} do
    first_params = %{"model" => "a"}
    second_params = %{"model" => "b"}

    task =
      task_fixture(%{
        run_id: run.id,
        name: "insert_models",
        map_index: 0,
        params: first_params
      })

    mapped_task =
      task_fixture(%{
        run_id: run.id,
        name: "insert_models",
        map_index: 1,
        params: second_params
      })

    task_id = task.id
    mapped_task_id = mapped_task.id

    dag_def = %{
      dag_def
      | tasks: %{
          "insert_models" => %{
            upstream: MapSet.new(["say_by"]),
            store_result: false,
            map_over: :say_by
          }
        }
    }

    Gust.DAGStageCoordinatorMock
    |> expect(:new, fn [^task_id, ^mapped_task_id] -> %{} end)

    Gust.DAGTaskRunnerSupervisorMock
    |> expect(:start_child, fn %Flows.Task{id: ^task_id, params: ^first_params},
                               _dag_def,
                               _pid,
                               opts ->
      refute Map.has_key?(opts, :params)
      {:ok, spawn(fn -> Process.sleep(10) end)}
    end)
    |> expect(:start_child, fn %Flows.Task{
                                 id: ^mapped_task_id,
                                 name: "insert_models",
                                 map_index: 1,
                                 params: ^second_params
                               },
                               _dag_def,
                               _pid,
                               opts ->
      refute Map.has_key?(opts, :params)
      {:ok, spawn(fn -> Process.sleep(10) end)}
    end)

    Gust.PubSub.subscribe_run(run.id)

    start_link_supervised!(
      {Gust.DAG.Runner.StageWorker,
       %{
         stage: [
           stage_entry(:ok, task),
           stage_entry(:ok, mapped_task)
         ],
         dag_def: dag_def,
         run_id: run.id
       }}
    )

    assert_receive {:dag, :run_status, %{run_id: _, status: :running}}, 400
    assert_receive {:dag, :run_status, %{run_id: _, status: :running}}, 400
  end

  test "uses existing mapped task instances when mapped task is already expanded", %{
    run: run,
    dag_def: dag_def
  } do
    first_params = %{"model" => "a"}
    second_params = %{"model" => "b"}

    task =
      task_fixture(%{
        run_id: run.id,
        name: "insert_models",
        map_index: 0,
        params: first_params
      })

    mapped_task =
      task_fixture(%{
        run_id: run.id,
        name: "insert_models",
        map_index: 1,
        params: second_params
      })

    task_id = task.id
    mapped_task_id = mapped_task.id

    dag_def = %{
      dag_def
      | tasks: %{
          "insert_models" => %{
            upstream: MapSet.new(["say_by"]),
            store_result: false,
            map_over: :say_by
          }
        }
    }

    Gust.DAGStageCoordinatorMock
    |> expect(:new, fn [^task_id, ^mapped_task_id] -> %{} end)

    Gust.DAGTaskRunnerSupervisorMock
    |> expect(:start_child, fn %Flows.Task{
                                 id: ^task_id,
                                 map_index: 0,
                                 params: ^first_params
                               },
                               _dag_def,
                               _pid,
                               opts ->
      refute Map.has_key?(opts, :params)
      {:ok, spawn(fn -> Process.sleep(10) end)}
    end)
    |> expect(:start_child, fn %Flows.Task{
                                 id: ^mapped_task_id,
                                 map_index: 1,
                                 params: ^second_params
                               },
                               _dag_def,
                               _pid,
                               opts ->
      refute Map.has_key?(opts, :params)
      {:ok, spawn(fn -> Process.sleep(10) end)}
    end)

    Gust.PubSub.subscribe_run(run.id)

    start_link_supervised!(
      {Gust.DAG.Runner.StageWorker,
       %{
         stage: [
           stage_entry(:ok, task),
           stage_entry(:ok, mapped_task)
         ],
         dag_def: dag_def,
         run_id: run.id
       }}
    )

    assert_receive {:dag, :run_status, %{run_id: _, status: :running}}, 400
    assert_receive {:dag, :run_status, %{run_id: _, status: :running}}, 400
  end

  test "does not start task when upstream failed", %{run: run, dag_def: dag_def} do
    task_fixture(%{run_id: run.id, name: "say_by", status: :failed})
    task = task_fixture(%{run_id: run.id, name: "insert_models"})
    task_id = task.id
    run_id = run.id

    dag_def = %{
      dag_def
      | tasks: %{
          "insert_models" => %{
            upstream: MapSet.new(["say_by"]),
            store_result: false,
            map_over: :say_by
          }
        }
    }

    expect_coord_new(task)

    Gust.DAGStageCoordinatorMock
    |> expect(:apply_task_result, fn _coord, _task, :upstream_failed ->
      {:finished, %{running: %{}}}
    end)

    Gust.PubSub.subscribe_run(run.id)

    runner_pid =
      start_link_supervised!(
        {Gust.DAG.Runner.StageWorker,
         %{stage: [stage_entry(:upstream_failed, task)], dag_def: dag_def, run_id: run.id}}
      )

    ref = Process.monitor(runner_pid)

    assert_receive {:dag, :run_status, %{run_id: ^run_id, status: :upstream_failed}}, 400
    assert Flows.get_task!(task_id).status == :upstream_failed

    assert Flows.get_tasks_by_name("insert_models", run.id) == [
             Flows.get_task!(task_id)
           ]

    assert_receive {:stage_completed, :upstream_failed}, 400
    assert_receive {:DOWN, ^ref, :process, _pid, :normal}, 400
  end

  describe "handle_continue/2 when upstream did not fail" do
    setup [:upstream_did_not_fail]

    test "tasks finished as reschedule and succeeded", %{task: task, run: run, dag_def: dag_def} do
      params = %{"model" => "retry-me"}
      {:ok, task} = Flows.update_task_mapping(task, 0, params)

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
          {Gust.DAG.Runner.StageWorker, %{stage: [stage_entry(:ok, task)], dag_def: dag_def}}
        )

      assert_receive {:dag, :run_status, %{run_id: ^run_id, status: :running}}, 300
      assert Flows.get_task!(task_id).status == :running

      ref = Process.monitor(runner_pid)

      error = %Ecto.CastError{message: "ops"}
      send(runner_pid, {:task_result, error, task.id, :error})

      Gust.DAGTaskRunnerSupervisorMock
      |> expect(:start_child, fn %Flows.Task{params: ^params, map_index: 0},
                                 %Gust.DAG.Definition{} = incoming_def,
                                 _pid,
                                 opts ->
        assert incoming_def.mod == mod
        refute Map.has_key?(opts, :params)
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
          {Gust.DAG.Runner.StageWorker, %{stage: [stage_entry(:ok, task)], dag_def: dag_def}}
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
          {Gust.DAG.Runner.StageWorker, %{stage: [stage_entry(:ok, task)], dag_def: dag_def}}
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
          {Gust.DAG.Runner.StageWorker, %{stage: [stage_entry(:ok, task)], dag_def: dag_def}}
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
          {Gust.DAG.Runner.StageWorker, %{stage: [stage_entry(:ok, task)], dag_def: dag_def}}
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
          {Gust.DAG.Runner.StageWorker, %{stage: [stage_entry(:ok, task)], dag_def: dag_def}}
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
