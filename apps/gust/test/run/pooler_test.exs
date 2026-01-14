defmodule Run.PoolerTest do
  alias Gust.PubSub
  alias Gust.Flows
  use Gust.DataCase

  import ExUnit.CaptureLog

  import Gust.FlowsFixtures
  import Mox

  alias Gust.Run.Pooler

  setup :verify_on_exit!
  setup :set_mox_from_context

  describe "handle_info/2 when message is :pool_runs" do
    test "claim enqueued runs" do
      dag = dag_fixture(%{name: "restart_me"})
      sec_dag = dag_fixture(%{name: "other_dag"})

      tick_delay = 250
      Application.put_env(:gust, :claim_runs_tick, 250)

      _restart_run = run_fixture(%{dag_id: dag.id, status: :enqueued})
      _restart_run_2 = run_fixture(%{dag_id: dag.id, status: :enqueued})
      _restart_run_with_error = run_fixture(%{dag_id: sec_dag.id, status: :enqueued})
      _created_run = run_fixture(%{dag_id: sec_dag.id, status: :created})

      dag_def = %Gust.DAG.Definition{name: dag.name}
      dag_def_error = %Gust.DAG.Definition{name: sec_dag.name, error: %{name: "Ops.."}}

      dag_id = dag.id
      sec_dag_id = sec_dag.id

      Gust.DAGLoaderMock
      |> expect(:get_definition, fn ^dag_id ->
        {:ok, dag_def}
      end)
      |> expect(:get_definition, fn ^dag_id ->
        {:ok, dag_def}
      end)
      |> expect(:get_definition, fn ^sec_dag_id ->
        {:ok, dag_def_error}
      end)

      Gust.DAGRunnerSupervisorMock
      |> expect(:start_child, 2, fn %Flows.Run{dag_id: ^dag_id} = run, ^dag_def ->
        Flows.update_run_status(run, :running)
        {:ok, spawn(fn -> :ok end)}
      end)

      {_, logs} =
        with_log(fn ->
          PubSub.subscribe_runs_claimed()

          start_link_supervised!(Pooler)

          assert_receive {:runs_claimed, %{node: _node}}, 200
          assert_receive {:runs_claimed, %{node: _node}}, tick_delay + 50

          Application.put_env(:gust, :claim_runs_tick, 2000)

          refute_receive {:runs_claimed, %{node: _node}}, 200

          assert_receive {:runs_claimed, %{node: _node}}, 200
        end)

      assert logs =~ "Not starting DAG: #{sec_dag.name} becasuse contains errors"
      assert logs =~ "Runs claimed: 3"
    end
  end

  describe "handle_info/2 when message is :pool_now" do
    test "claim enqueued runs" do
      dag = dag_fixture(%{name: "restart_me"})

      restart_run = run_fixture(%{dag_id: dag.id, status: :created})

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

          start_link_supervised!(Pooler)
          assert_receive {:runs_claimed, %{node: _node}}, 200

          {:ok, run} = Flows.update_run_status(restart_run, :enqueued)

          Gust.PubSub.broadcast_run_dispatch(run.id)

          assert_receive {:runs_claimed, %{node: _node}}, 200
        end)

      assert logs =~ "Runs claimed: 1"
    end
  end
end
