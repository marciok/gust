defmodule Gust.Run.ClaimerTest do
  alias Gust.Flows
  alias Gust.PubSub
  use Gust.DataCase

  import ExUnit.CaptureLog

  import Gust.FlowsFixtures
  import Mox

  alias Gust.Run.Claimer

  setup :verify_on_exit!
  setup :set_mox_from_context

  setup do
    replace_env(:run_dispatcher, Gust.Run.Pooler)
    replace_env(:claim_runs_tick, 9_999_999)
    replace_env(:claim_runs_batch_size, 50)

    start_supervised!(Gust.Run.Pooler)
    stub(Gust.DAGLoaderMock, :get_definitions, fn -> %{} end)

    :ok
  end

  describe "handle_info/2 when the dispatcher initializes" do
    test "claims enqueued runs" do
      dag = dag_fixture(%{name: "restart_me"})
      sec_dag = dag_fixture(%{name: "other_dag"})

      restart_run = run_fixture(%{dag_id: dag.id, status: :enqueued})
      restart_run_2 = run_fixture(%{dag_id: dag.id, status: :enqueued})
      restart_run_with_error = run_fixture(%{dag_id: sec_dag.id, status: :enqueued})

      dag_def = %Gust.DAG.Definition{name: dag.name}
      dag_def_error = %Gust.DAG.Definition{name: sec_dag.name, error: %{name: "Ops.."}}

      dag_id = dag.id
      sec_dag_id = sec_dag.id

      Gust.DAGLoaderMock
      |> expect(:get_definition, fn ^dag_id -> {:ok, dag_def} end)
      |> expect(:get_definition, fn ^dag_id -> {:ok, dag_def} end)
      |> expect(:get_definition, fn ^sec_dag_id -> {:ok, dag_def_error} end)

      Gust.RunClaimMock
      |> expect(:next_run, fn _sequential_dag_ids -> restart_run end)
      |> expect(:next_run, fn _sequential_dag_ids -> restart_run_2 end)
      |> expect(:next_run, fn _sequential_dag_ids -> restart_run_with_error end)
      |> expect(:next_run, fn _sequential_dag_ids -> nil end)

      Gust.DAGRunnerSupervisorMock
      |> expect(:start_child, 2, fn %Flows.Run{dag_id: ^dag_id} = run, ^dag_def ->
        Flows.update_run_status(run, :running)
        {:ok, spawn(fn -> :ok end)}
      end)

      {_, logs} =
        with_log(fn ->
          PubSub.subscribe_runs_claimed()

          start_link_supervised!(Claimer)

          assert_receive {:runs_claimed, %{node: _node}}, 200
        end)

      assert logs =~ "Not starting DAG: #{sec_dag.name} because contains errors"
      assert logs =~ "Runs claimed: 3"
    end
  end

  describe "handle_info/2 when a dispatch event arrives" do
    test "claims enqueued runs" do
      dag = dag_fixture(%{name: "restart_me"})

      run = run_fixture(%{dag_id: dag.id, status: :created})

      Gust.RunClaimMock |> expect(:next_run, fn _sequential_dag_ids -> run end)
      Gust.RunClaimMock |> expect(:next_run, fn _sequential_dag_ids -> nil end)

      dag_def = %Gust.DAG.Definition{name: dag.name}
      dag_id = dag.id

      Gust.DAGLoaderMock
      |> expect(:get_definition, fn ^dag_id ->
        {:ok, dag_def}
      end)

      Gust.DAGRunnerSupervisorMock
      |> expect(:start_child, 1, fn %Flows.Run{dag_id: ^dag_id} = run, ^dag_def ->
        Flows.update_run_status(run, :running)
        {:ok, spawn(fn -> :ok end)}
      end)

      {_, logs} =
        with_log(fn ->
          PubSub.subscribe_runs_claimed()

          start_link_supervised!(Claimer)
          Process.sleep(200)
          Gust.PubSub.broadcast_run_dispatch_wake()

          assert_receive {:runs_claimed, %{node: _node}}, 200
        end)

      assert logs =~ "Runs claimed: 1"
    end

    test "continues claiming when a batch is full" do
      Application.put_env(:gust, :claim_runs_batch_size, 2)

      dag = dag_fixture(%{name: "drain_full_batch"})
      runs = Enum.map(1..3, fn _ -> run_fixture(%{dag_id: dag.id, status: :enqueued}) end)
      dag_def = %Gust.DAG.Definition{name: dag.name}

      Gust.RunClaimMock
      |> expect(:next_run, fn _sequential_dag_ids -> Enum.at(runs, 0) end)
      |> expect(:next_run, fn _sequential_dag_ids -> Enum.at(runs, 1) end)
      |> expect(:next_run, fn _sequential_dag_ids -> Enum.at(runs, 2) end)
      |> expect(:next_run, fn _sequential_dag_ids -> nil end)

      Gust.DAGLoaderMock
      |> expect(:get_definition, 3, fn _dag_id -> {:ok, dag_def} end)

      Gust.DAGRunnerSupervisorMock
      |> expect(:start_child, 3, fn _run, ^dag_def ->
        {:ok, spawn(fn -> :ok end)}
      end)

      PubSub.subscribe_runs_claimed()
      start_link_supervised!(Claimer)

      assert_receive {:runs_claimed, %{node: _node}}, 200
      assert_receive {:runs_claimed, %{node: _node}}, 200
    end
  end

  describe "sequential dags" do
    test "passes the ids of sequential dags to the claim" do
      sequential = %Gust.DAG.Definition{name: "seq", options: [runs: [concurrency: :sequential]]}
      parallel = %Gust.DAG.Definition{name: "par", options: [runs: [concurrency: :parallel]]}
      default = %Gust.DAG.Definition{name: "default"}

      stub(Gust.DAGLoaderMock, :get_definitions, fn ->
        %{
          1 => {:ok, sequential},
          2 => {:ok, parallel},
          3 => {:ok, default},
          4 => {:error, :enoent}
        }
      end)

      test_pid = self()

      Gust.RunClaimMock
      |> expect(:next_run, fn sequential_dag_ids ->
        send(test_pid, {:sequential_dag_ids, sequential_dag_ids})
        nil
      end)

      start_link_supervised!(Claimer)

      assert_receive {:sequential_dag_ids, [1]}, 200
    end
  end
end
