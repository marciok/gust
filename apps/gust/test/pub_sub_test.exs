defmodule Gust.PubSubTest do
  use ExUnit.Case, async: true

  describe "subscribe_run/1 & broadcast_run_status/2" do
    test "delivers the expected message to the right topic" do
      run_id = "r-123"
      status = :running

      assert :ok == Gust.PubSub.subscribe_run(run_id)
      assert :ok == Gust.PubSub.broadcast_run_status(run_id, status)

      assert_receive {:dag, :run_status, %{run_id: ^run_id, status: ^status}}
    end

    test "does not leak messages to other run topics" do
      subscribed = "r-aaa"
      other = "r-bbb"

      assert :ok == Gust.PubSub.subscribe_run(subscribed)
      assert :ok == Gust.PubSub.broadcast_run_status(other, :finished)

      refute_receive _any, 50
    end
  end

  describe "subscribe_runs_for_dag/1 & broadcast_run_started/2" do
    test "delivers the expected message to the dag:scheduled topic" do
      dag_id = "d-42"
      run_id = "r-999"

      assert :ok == Gust.PubSub.subscribe_runs_for_dag(dag_id)
      assert :ok == Gust.PubSub.broadcast_run_started(dag_id, run_id)

      assert_receive {:dag, :run_started, %{run_id: ^run_id}}
    end

    test "does not leak messages to other dag:scheduled topics" do
      subscribed_dag = "d-a"
      other_dag = "d-b"

      assert :ok == Gust.PubSub.subscribe_runs_for_dag(subscribed_dag)
      assert :ok == Gust.PubSub.broadcast_run_started(other_dag, "r-x")

      refute_receive _any, 50
    end
  end
end
