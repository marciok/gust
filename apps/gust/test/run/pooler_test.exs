defmodule Gust.Run.PoolerTest do
  use Gust.DataCase, async: false

  import Gust.FlowsFixtures

  alias Gust.Flows
  alias Gust.PubSub
  alias Gust.Run.Pooler

  setup do
    previous_tick = Application.get_env(:gust, :claim_runs_tick)
    Application.put_env(:gust, :claim_runs_tick, 9_999_999)

    on_exit(fn -> restore_env(:claim_runs_tick, previous_tick) end)

    :ok
  end

  test "enqueues a run and broadcasts its status and dispatch" do
    dag = dag_fixture(%{name: "pooler_enqueue"})
    run = run_fixture(%{dag_id: dag.id})

    PubSub.subscribe_run(run.id)
    PubSub.subscribe_run_dispatch()

    assert %{id: run_id, status: :enqueued} = Pooler.enqueue(run)
    assert run_id == run.id
    assert %{status: :enqueued} = Flows.get_run!(run.id)

    assert_receive {:dag, :run_status, %{run_id: ^run_id, status: :enqueued}}
    assert_receive {:run_dispatch, :dispatch_run, %{run_id: ^run_id}}
  end

  test "polls safely before setup and wakes the registered claimer afterward" do
    start_supervised!(Pooler)

    send(Pooler, :poll_runs)
    PubSub.broadcast_run_dispatch(123)
    refute_receive :claim_runs

    assert :ok = Pooler.setup()
    send(Pooler, :poll_runs)
    assert_receive :claim_runs
  end

  test "forwards PubSub dispatch events to the registered claimer" do
    start_supervised!(Pooler)
    assert :ok = Pooler.setup()

    PubSub.broadcast_run_dispatch(123)

    assert_receive :claim_runs
  end

  defp restore_env(key, nil), do: Application.delete_env(:gust, key)
  defp restore_env(key, value), do: Application.put_env(:gust, key, value)
end
