defmodule Gust.Run.PoolerTest do
  use Gust.DataCase, async: false

  import Gust.FlowsFixtures

  alias Gust.Flows
  alias Gust.PubSub
  alias Gust.Run.Dispatcher
  alias Gust.Run.Pooler

  setup do
    replace_env(:claim_runs_tick, 9_999_999)

    :ok
  end

  test "enqueues a run and broadcasts its status and dispatch" do
    dag = dag_fixture(%{name: "pooler_enqueue"})
    run = run_fixture(%{dag_id: dag.id})

    PubSub.subscribe_run(run.id)
    PubSub.subscribe_run_dispatch()

    assert %{id: run_id, status: :enqueued} = Dispatcher.enqueue(run)
    assert run_id == run.id
    assert %{status: :enqueued} = Flows.get_run!(run.id)

    assert_receive {:dag, :run_status, %{run_id: ^run_id, status: :enqueued}}
    assert_receive {:run_dispatch, :wake}
  end

  test "enqueues a batch with one dispatch wake" do
    dag = dag_fixture(%{name: "pooler_enqueue_batch"})
    runs = [run_fixture(%{dag_id: dag.id}), run_fixture(%{dag_id: dag.id})]

    Enum.each(runs, &PubSub.subscribe_run(&1.id))
    PubSub.subscribe_run_dispatch()

    assert [%{status: :enqueued}, %{status: :enqueued}] = Pooler.enqueue_all(runs)

    Enum.each(runs, fn run ->
      assert %{status: :enqueued} = Flows.get_run!(run.id)
      assert_receive {:dag, :run_status, %{run_id: run_id, status: :enqueued}}
      assert run_id in Enum.map(runs, & &1.id)
    end)

    assert_receive {:run_dispatch, :wake}
    refute_receive {:run_dispatch, :wake}, 50
  end

  test "dispatcher ignores empty batches" do
    PubSub.subscribe_run_dispatch()

    assert [] = Dispatcher.enqueue_all([])
    refute_receive {:run_dispatch, :wake}, 50
  end

  test "polls safely before setup and wakes the registered claimer afterward" do
    start_supervised!(Pooler)

    send(Pooler, :poll_runs)
    PubSub.broadcast_run_dispatch_wake()
    refute_receive :claim_runs

    assert :ok = Pooler.setup()
    send(Pooler, :poll_runs)
    assert_receive :claim_runs
  end

  test "forwards PubSub dispatch events to the registered claimer" do
    start_supervised!(Pooler)
    assert :ok = Pooler.setup()

    PubSub.broadcast_run_dispatch_wake()

    assert_receive :claim_runs
  end
end
