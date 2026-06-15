defmodule DAG.Runner.DagWorkerTest do
  use Gust.DataCase, async: false

  import Mox
  import Gust.FlowsFixtures
  alias Gust.{Flows, Repo}

  setup :verify_on_exit!
  setup :set_mox_from_context

  defp expect_stage_processing(task_names, status \\ :ok) do
    statuses = List.duplicate(status, length(task_names))
    expect_stage_processing_statuses(Enum.zip(task_names, statuses))
  end

  defp expect_stage_processing_statuses(task_names_with_statuses) do
    Enum.reduce(task_names_with_statuses, Gust.DAGStageCoordinatorMock, fn {task_name, status},
                                                                           mock ->
      expect(mock, :process_task, fn %Flows.Task{name: ^task_name}, _tasks -> status end)
    end)
  end

  defp assert_stage_entry({expected_status, task}, expected_task_names, run_id) do
    assert expected_status == :ok
    assert task.name in expected_task_names
    assert task.run_id == run_id
  end

  def worker_starts_normally(%{run: run, dag_def: dag_def} = setup) do
    Application.put_env(:gust, :reclaim_run_delay, 0)
    Gust.PubSub.subscribe_run(run.id)
    Gust.PubSub.subscribe_runs_for_dag(run.dag_id)

    hi_task_id = task_fixture(%{name: "hi", status: :succeeded, run_id: run.id}).id
    hey_task_id = task_fixture(%{name: "hey", status: :running, run_id: run.id}).id
    run_id = run.id

    expect_stage_processing(["hi", "hey", "ho"])

    Gust.DAGStageRunnerSupervisorMock
    |> expect(:start_child, fn ^dag_def,
                               [
                                 {:ok, %Flows.Task{id: ^hi_task_id}},
                                 {:ok, %Flows.Task{id: ^hey_task_id}},
                                 {:ok, %Flows.Task{}}
                               ],
                               _pid ->
      {:ok, spawn(fn -> Process.sleep(10) end)}
    end)

    Map.merge(setup, %{run_id: run_id, task_id: hey_task_id})
  end

  setup do
    Application.put_env(:gust, :dag_adapter, elixir: %{runtime: Gust.RuntimeAdapterMock})
    Application.put_env(:gust, :reclaim_run_delay, 99_999_999)
    dag = dag_fixture()

    run = run_fixture(%{dag_id: dag.id, claim_token: Ecto.UUID.generate()})

    dag_def = %Gust.DAG.Definition{
      mod: MyDag,
      stages: [["hi", "hey", "ho"], ["bye"]]
    }

    Gust.RuntimeAdapterMock |> expect(:setup, fn dag_def, _runtime -> dag_def end)
    %{run: run, dag_def: dag_def}
  end

  describe "handle_info/2" do
    setup [:worker_starts_normally]

    test "start stage worker", %{run: run, dag_def: dag_def, run_id: run_id, task_id: task_id} do
      Gust.RunClaimMock
      |> expect(:renew_run, fn ^run_id, _token -> run end)
      |> expect(:renew_run, fn ^run_id, _token -> nil end)

      runner_pid = start_supervised!({Gust.DAG.Runner.DAGWorker, %{run: run, dag_def: dag_def}})

      ref = Process.monitor(runner_pid)

      assert_receive {:dag, :run_started, %{run_id: ^run_id}}, 200
      assert_receive {:dag, :run_status, %{run_id: ^run_id, status: :running}}, 200

      assert %Flows.Run{status: :running} = Flows.get_run!(run.id)
      assert %Flows.Task{status: :created} = Flows.get_task!(task_id)

      assert_receive {:DOWN, ^ref, :process, _pid, :normal}, 600
    end
  end

  describe "handle_info/2, stage_completed unsuccessfully" do
    test "task cancelled", %{run: run, dag_def: dag_def} do
      Gust.PubSub.subscribe_run(run.id)
      last_stage = dag_def.stages |> List.last()
      dag_def = %Gust.DAG.Definition{dag_def | stages: [last_stage]}
      run_id = run.id
      Gust.RuntimeAdapterMock |> expect(:teardown, fn _dag_def, _runtime -> :ok end)

      expect_stage_processing(last_stage)

      Gust.DAGStageRunnerSupervisorMock
      |> expect(:start_child, fn ^dag_def, stage, _pid ->
        Enum.each(stage, &assert_stage_entry(&1, last_stage, run.id))

        {:ok, spawn(fn -> Process.sleep(10) end)}
      end)

      runner_pid =
        start_supervised!({Gust.DAG.Runner.DAGWorker, %{run: run, dag_def: dag_def}})

      ref = Process.monitor(runner_pid)

      assert_receive {:dag, :run_status, %{run_id: ^run_id, status: :running}}, 400

      send(runner_pid, {:stage_completed, :cancelled})

      assert_receive {:dag, :run_status, %{run_id: ^run_id, status: :failed}}, 400
      assert Flows.get_run!(run.id).status == :failed

      assert_receive {:DOWN, ^ref, :process, _pid, :normal}, 200
    end

    test "upstream failed", %{run: run, dag_def: dag_def} do
      Gust.PubSub.subscribe_run(run.id)
      last_stage = dag_def.stages |> List.last()
      dag_def = %Gust.DAG.Definition{dag_def | stages: [last_stage]}
      run_id = run.id
      Gust.RuntimeAdapterMock |> expect(:teardown, fn _dag_def, _runtime -> :ok end)

      expect_stage_processing(last_stage)

      Gust.DAGStageRunnerSupervisorMock
      |> expect(:start_child, fn ^dag_def, stage, _pid ->
        Enum.each(stage, &assert_stage_entry(&1, last_stage, run.id))

        {:ok, spawn(fn -> Process.sleep(10) end)}
      end)

      runner_pid =
        start_supervised!({Gust.DAG.Runner.DAGWorker, %{run: run, dag_def: dag_def}})

      ref = Process.monitor(runner_pid)

      assert_receive {:dag, :run_status, %{run_id: ^run_id, status: :running}}, 400

      send(runner_pid, {:stage_completed, :upstream_failed})

      assert_receive {:dag, :run_status, %{run_id: ^run_id, status: :failed}}, 400
      assert %Flows.Run{status: :failed} = Flows.get_run!(run.id)

      assert_receive {:DOWN, ^ref, :process, _pid, :normal}, 200
    end

    test "next stage is empty and callback is set", %{run: run, dag_def: dag_def} do
      Gust.RuntimeAdapterMock
      |> expect(:teardown, fn _dag_def, _runtime -> :ok end)
      |> expect(:on_finished_callback, fn _dag_def, _callback_fn_name, _run, _status -> :ok end)

      Gust.PubSub.subscribe_run(run.id)
      last_stage = dag_def.stages |> List.last()

      dag_def = %Gust.DAG.Definition{
        dag_def
        | stages: [last_stage],
          mod: TestModCallback,
          options: [on_finished_callback: :callback]
      }

      run_id = run.id

      expect_stage_processing(last_stage)

      Gust.DAGStageRunnerSupervisorMock
      |> expect(:start_child, fn ^dag_def, stage, _pid ->
        Enum.each(stage, &assert_stage_entry(&1, last_stage, run.id))

        {:ok, spawn(fn -> Process.sleep(10) end)}
      end)

      runner_pid =
        start_supervised!({Gust.DAG.Runner.DAGWorker, %{run: run, dag_def: dag_def}})

      ref = Process.monitor(runner_pid)

      send(runner_pid, {:stage_completed, :error})

      assert_receive {:dag, :run_status, %{run_id: ^run_id, status: :failed}}, 400
      assert Repo.get!(Flows.Run, run.id).status == :failed

      assert_receive {:DOWN, ^ref, :process, _pid, :normal}, 200
    end
  end

  describe "handle_info/2, when run have running and done tasks " do
    test "start_child with restarting tasks", %{run: run, dag_def: dag_def} do
      hey_t = task_fixture(%{run_id: run.id, name: "hey", status: :running})
      ho_t = task_fixture(%{run_id: run.id, name: "ho", status: :failed})

      expect_stage_processing(["hi", "hey", "ho"])

      Gust.DAGStageRunnerSupervisorMock
      |> expect(:start_child, fn ^dag_def, stage, _pid ->
        [
          {:ok, %Flows.Task{id: t1}},
          {:ok, %Flows.Task{id: t2}},
          {:ok, %Flows.Task{id: t3}}
        ] = stage

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

    test "start_child with expanded mapped task instances", %{run: run, dag_def: dag_def} do
      first_params = %{"model" => "a"}
      second_params = %{"model" => "b"}

      dag_def = %Gust.DAG.Definition{
        dag_def
        | stages: [["insert_models"]],
          tasks: %{
            "insert_models" => %{
              upstream: MapSet.new(["say_by"]),
              store_result: false,
              map_over: :say_by
            }
          }
      }

      Gust.DAGStageCoordinatorMock
      |> expect(:process_task, fn %Flows.Task{name: "insert_models"}, _tasks ->
        {:expand_task, [first_params, second_params]}
      end)

      Gust.DAGTaskExpanderMock
      |> expect(:expand_over, fn [^first_params, ^second_params],
                                 %Flows.Task{name: "insert_models", run_id: run_id} = task,
                                 run_id,
                                 create_fn ->
        second_task = create_fn.(task.name, 1)

        [
          {:ok, {%Flows.Task{task | map_index: 0, params: first_params}, first_params}},
          {:ok, {%Flows.Task{second_task | params: second_params}, second_params}}
        ]
      end)

      Gust.DAGStageRunnerSupervisorMock
      |> expect(:start_child, fn ^dag_def,
                                 [
                                   {:ok,
                                    %Flows.Task{
                                      name: "insert_models",
                                      run_id: run_id,
                                      map_index: 0,
                                      params: ^first_params
                                    }},
                                   {:ok,
                                    %Flows.Task{
                                      name: "insert_models",
                                      run_id: run_id,
                                      map_index: 1,
                                      params: ^second_params
                                    }}
                                 ],
                                 _pid ->
        assert run_id == run.id
        {:ok, spawn(fn -> Process.sleep(10) end)}
      end)

      runner_pid =
        start_supervised!({Gust.DAG.Runner.DAGWorker, %{run: run, dag_def: dag_def}})

      ref = Process.monitor(runner_pid)

      refute_receive {:DOWN, ^ref, :process, _pid, :normal}, 200
    end

    test "ensure_task resets an existing running mapped task to created", %{
      run: run,
      dag_def: dag_def
    } do
      _base_task =
        task_fixture(%{
          run_id: run.id,
          name: "insert_models",
          status: :created
        })

      existing_task =
        task_fixture(%{
          run_id: run.id,
          name: "insert_models",
          status: :created,
          map_index: 1
        })

      params = %{"model" => "existing"}

      dag_def = %Gust.DAG.Definition{
        dag_def
        | stages: [["insert_models"]],
          tasks: %{
            "insert_models" => %{
              upstream: MapSet.new(["say_by"]),
              store_result: false,
              map_over: :say_by
            }
          }
      }

      Gust.DAGStageCoordinatorMock
      |> expect(:process_task, fn %Flows.Task{map_index: nil}, _tasks ->
        {:ok, _task} = Flows.update_task_status(existing_task, :running)
        {:expand_task, [params]}
      end)
      |> expect(:process_task, fn %Flows.Task{id: task_id, map_index: 1}, _tasks ->
        assert task_id == existing_task.id
        :already_processed
      end)

      Gust.DAGTaskExpanderMock
      |> expect(:expand_over, fn [^params],
                                 %Flows.Task{name: "insert_models"},
                                 run_id,
                                 create_fn ->
        assert run_id == run.id
        task = create_fn.("insert_models", 1)
        assert task.id == existing_task.id
        assert task.status == :created
        assert Flows.get_task!(task.id).status == :created
        []
      end)

      Gust.DAGStageRunnerSupervisorMock
      |> expect(:start_child, fn ^dag_def,
                                 [
                                   {:already_processed, %Flows.Task{id: task_id, map_index: 1}}
                                 ],
                                 run_id ->
        assert task_id == existing_task.id
        assert run_id == run.id
        {:ok, spawn(fn -> Process.sleep(10) end)}
      end)

      runner_pid =
        start_supervised!({Gust.DAG.Runner.DAGWorker, %{run: run, dag_def: dag_def}})

      ref = Process.monitor(runner_pid)

      refute_receive {:DOWN, ^ref, :process, _pid, :normal}, 200
    end

    test "ensure_task returns an existing non-running mapped task unchanged", %{
      run: run,
      dag_def: dag_def
    } do
      _base_task =
        task_fixture(%{
          run_id: run.id,
          name: "insert_models",
          status: :created
        })

      existing_task =
        task_fixture(%{
          run_id: run.id,
          name: "insert_models",
          status: :succeeded,
          map_index: 1
        })

      params = %{"model" => "existing"}

      dag_def = %Gust.DAG.Definition{
        dag_def
        | stages: [["insert_models"]],
          tasks: %{
            "insert_models" => %{
              upstream: MapSet.new(["say_by"]),
              store_result: false,
              map_over: :say_by
            }
          }
      }

      Gust.DAGStageCoordinatorMock
      |> expect(:process_task, fn %Flows.Task{map_index: nil}, _tasks ->
        {:expand_task, [params]}
      end)
      |> expect(:process_task, fn %Flows.Task{id: task_id, map_index: 1}, _tasks ->
        assert task_id == existing_task.id
        :already_processed
      end)

      Gust.DAGTaskExpanderMock
      |> expect(:expand_over, fn [^params],
                                 %Flows.Task{name: "insert_models"},
                                 run_id,
                                 create_fn ->
        assert run_id == run.id
        task = create_fn.("insert_models", 1)
        assert task.id == existing_task.id
        assert task.status == :succeeded
        []
      end)

      Gust.DAGStageRunnerSupervisorMock
      |> expect(:start_child, fn ^dag_def,
                                 [
                                   {:already_processed, %Flows.Task{id: task_id, map_index: 1}}
                                 ],
                                 run_id ->
        assert task_id == existing_task.id
        assert run_id == run.id
        assert Flows.get_task!(task_id).status == :succeeded
        {:ok, spawn(fn -> Process.sleep(10) end)}
      end)

      runner_pid =
        start_supervised!({Gust.DAG.Runner.DAGWorker, %{run: run, dag_def: dag_def}})

      ref = Process.monitor(runner_pid)

      refute_receive {:DOWN, ^ref, :process, _pid, :normal}, 200
    end

    test "starts the stage with a non-recoverable error when mapped params cannot expand", %{
      run: run,
      dag_def: dag_def
    } do
      error = %RuntimeError{message: "upstream result cannot be expanded"}

      dag_def = %Gust.DAG.Definition{
        dag_def
        | stages: [["insert_models"]],
          tasks: %{
            "insert_models" => %{
              upstream: MapSet.new(["say_by"]),
              store_result: false,
              map_over: :say_by
            }
          }
      }

      Gust.DAGStageCoordinatorMock
      |> expect(:process_task, fn %Flows.Task{name: "insert_models"}, _tasks ->
        {:expand_task_error, error}
      end)

      Gust.DAGStageRunnerSupervisorMock
      |> expect(:start_child, fn ^dag_def,
                                 [
                                   {{:non_recoverable_error, ^error},
                                    %Flows.Task{
                                      name: "insert_models",
                                      run_id: run_id
                                    }}
                                 ],
                                 run_id ->
        assert run_id == run.id
        {:ok, spawn(fn -> Process.sleep(10) end)}
      end)

      runner_pid =
        start_supervised!({Gust.DAG.Runner.DAGWorker, %{run: run, dag_def: dag_def}})

      ref = Process.monitor(runner_pid)

      refute_receive {:DOWN, ^ref, :process, _pid, :normal}, 200
    end

    test "start_child with existing mapped task instances and their params", %{
      run: run,
      dag_def: dag_def
    } do
      first_params = %{"model" => "a"}
      second_params = %{"model" => "b"}

      first_task =
        task_fixture(%{
          run_id: run.id,
          name: "insert_models",
          status: :succeeded,
          map_index: 0
        })

      second_task =
        task_fixture(%{
          run_id: run.id,
          name: "insert_models",
          status: :running,
          map_index: 1
        })

      dag_def = %Gust.DAG.Definition{dag_def | stages: [["insert_models"]]}

      Gust.DAGStageCoordinatorMock
      |> expect(:process_task, fn %Flows.Task{id: task_id, map_index: 0}, _tasks
                                  when task_id == first_task.id ->
        {:already_expanded, first_params}
      end)
      |> expect(:process_task, fn %Flows.Task{id: task_id, map_index: 1}, _tasks
                                  when task_id == second_task.id ->
        {:already_expanded, second_params}
      end)

      Gust.DAGStageRunnerSupervisorMock
      |> expect(:start_child, fn ^dag_def,
                                 [
                                   {:ok,
                                    %Flows.Task{
                                      id: first_task_id,
                                      map_index: 0,
                                      params: ^first_params
                                    }},
                                   {:ok,
                                    %Flows.Task{
                                      id: second_task_id,
                                      map_index: 1,
                                      params: ^second_params
                                    }}
                                 ],
                                 _pid ->
        assert first_task_id == first_task.id
        assert second_task_id == second_task.id
        assert Flows.get_task!(second_task.id).status == :created

        {:ok, spawn(fn -> Process.sleep(10) end)}
      end)

      runner_pid =
        start_supervised!({Gust.DAG.Runner.DAGWorker, %{run: run, dag_def: dag_def}})

      ref = Process.monitor(runner_pid)

      refute_receive {:DOWN, ^ref, :process, _pid, :normal}, 200
    end

    test "empty final mapped stage skips its placeholder task and completes the run", %{
      run: run,
      dag_def: dag_def
    } do
      run_id = run.id

      dag_def = %Gust.DAG.Definition{
        dag_def
        | stages: [["insert_models"]],
          tasks: %{
            "insert_models" => %{
              upstream: MapSet.new(["say_by"]),
              store_result: false,
              map_over: :say_by
            }
          }
      }

      Gust.PubSub.subscribe_run(run_id)

      Gust.DAGStageCoordinatorMock
      |> expect(:process_task, fn %Flows.Task{name: "insert_models"}, _tasks ->
        {:expand_task, []}
      end)

      Gust.DAGStageRunnerSupervisorMock
      |> expect(:start_child, fn ^dag_def,
                                 [
                                   {:skipped, %Flows.Task{name: "insert_models", run_id: ^run_id}}
                                 ],
                                 ^run_id ->
        send(self(), {:stage_completed, :skipped})
        {:ok, spawn(fn -> Process.sleep(10) end)}
      end)

      Gust.RuntimeAdapterMock
      |> expect(:teardown, fn ^dag_def, _runtime_id -> :ok end)

      runner_pid =
        start_supervised!({Gust.DAG.Runner.DAGWorker, %{run: run, dag_def: dag_def}})

      ref = Process.monitor(runner_pid)

      assert_receive {:dag, :run_status, %{run_id: ^run_id, status: :running}}, 400
      assert_receive {:dag, :run_status, %{run_id: ^run_id, status: :succeeded}}, 400
      assert_receive {:DOWN, ^ref, :process, ^runner_pid, :normal}, 200
      assert %Flows.Run{status: :succeeded} = Flows.get_run!(run_id)
    end

    test "empty mapped stage skips its placeholder task and advances to the next stage",
         %{
           run: run,
           dag_def: dag_def
         } do
      run_id = run.id
      test_pid = self()

      dag_def = %Gust.DAG.Definition{
        dag_def
        | stages: [["insert_models"], ["bye"]],
          tasks: %{
            "insert_models" => %{
              upstream: MapSet.new(["say_by"]),
              store_result: false,
              map_over: :say_by
            },
            "bye" => %{
              upstream: MapSet.new(["insert_models"]),
              store_result: false,
              map_over: nil
            }
          }
      }

      Gust.DAGStageCoordinatorMock
      |> expect(:process_task, fn
        %Flows.Task{name: "insert_models"}, _tasks -> {:expand_task, []}
      end)
      |> expect(:process_task, fn
        %Flows.Task{name: "bye"}, _tasks -> :ok
      end)

      Gust.DAGStageRunnerSupervisorMock
      |> expect(:start_child, fn ^dag_def,
                                 [
                                   {:skipped, %Flows.Task{name: "insert_models", run_id: ^run_id}}
                                 ],
                                 ^run_id ->
        send(self(), {:stage_completed, :skipped})
        {:ok, spawn(fn -> Process.sleep(10) end)}
      end)

      Gust.DAGStageRunnerSupervisorMock
      |> expect(:start_child, fn ^dag_def,
                                 [{:ok, %Flows.Task{name: "bye", run_id: ^run_id}}],
                                 ^run_id ->
        send(test_pid, :next_stage_started)
        {:ok, spawn(fn -> Process.sleep(10) end)}
      end)

      runner_pid =
        start_supervised!({Gust.DAG.Runner.DAGWorker, %{run: run, dag_def: dag_def}})

      ref = Process.monitor(runner_pid)

      assert_receive :next_stage_started, 400
      refute_receive {:DOWN, ^ref, :process, ^runner_pid, _reason}, 200
    end
  end

  describe "handle_info/2, stage_completed successfully" do
    test "next stage start", %{run: run, dag_def: dag_def} do
      first_stage = dag_def.stages |> List.first()
      last_stage = dag_def.stages |> List.last()

      expect_stage_processing(first_stage)

      Gust.DAGStageRunnerSupervisorMock
      |> expect(:start_child, fn ^dag_def, stage, _pid ->
        Enum.each(stage, &assert_stage_entry(&1, first_stage, run.id))

        {:ok, spawn(fn -> Process.sleep(10) end)}
      end)

      expect_stage_processing(last_stage)

      Gust.DAGStageRunnerSupervisorMock
      |> expect(:start_child, fn ^dag_def, stage, _pid ->
        Enum.each(stage, &assert_stage_entry(&1, last_stage, run.id))

        {:ok, spawn(fn -> Process.sleep(10) end)}
      end)

      runner_pid =
        start_supervised!({Gust.DAG.Runner.DAGWorker, %{run: run, dag_def: dag_def}})

      ref = Process.monitor(runner_pid)

      send(runner_pid, {:stage_completed, :ok})

      refute_receive {:DOWN, ^ref, :process, _pid, :normal}, 200
    end

    test "next stage is empty", %{run: run, dag_def: dag_def} do
      Gust.RuntimeAdapterMock |> expect(:teardown, fn _dag_def, _runtime -> :ok end)
      Gust.PubSub.subscribe_run(run.id)
      last_stage = dag_def.stages |> List.last()
      dag_def = %Gust.DAG.Definition{dag_def | stages: [last_stage]}
      run_id = run.id

      expect_stage_processing(last_stage)

      Gust.DAGStageRunnerSupervisorMock
      |> expect(:start_child, fn ^dag_def, stage, _pid ->
        Enum.each(stage, &assert_stage_entry(&1, last_stage, run.id))

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
