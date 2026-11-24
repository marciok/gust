defmodule Gust.Run.PrunerTest do
  use Gust.DataCase, async: false
  import Gust.FlowsFixtures
  import Mox

  alias Gust.DAG.Definition
  alias Gust.Flows
  alias Gust.Flows.{Log, Run, Task}
  alias Gust.Run.Pruner

  setup :verify_on_exit!

  defp runs!(dag, statuses) do
    Enum.map(statuses, &run_fixture(%{dag_id: dag.id, status: &1}))
  end

  defp run_ids(dag) do
    Run |> where([r], r.dag_id == ^dag.id) |> order_by(:id) |> select([r], r.id) |> Repo.all()
  end

  describe "prune/3" do
    test "keeps exactly the max_count newest finished runs" do
      dag = dag_fixture()
      runs = runs!(dag, List.duplicate(:succeeded, 3) ++ List.duplicate(:failed, 3))
      kept = runs |> Enum.take(-4) |> Enum.map(& &1.id)

      assert 2 == Pruner.prune(dag.id, 4)
      assert kept == run_ids(dag)
    end

    test "never deletes or counts unfinished runs" do
      dag = dag_fixture()
      unfinished = [:created, :enqueued, :starting, :running, :waiting]

      [old_finished | _] = runs = runs!(dag, [:succeeded | unfinished] ++ [:succeeded, :failed])

      assert 1 == Pruner.prune(dag.id, 2)
      assert Enum.map(runs, & &1.id) -- [old_finished.id] == run_ids(dag)
    end

    test "deletes nothing when the dag has at most max_count finished runs" do
      dag = dag_fixture()
      runs!(dag, [:succeeded, :failed])

      assert 0 == Pruner.prune(dag.id, 2)
      assert 2 == length(run_ids(dag))
    end

    test "only prunes runs of the given dag" do
      dag = dag_fixture()
      other_dag = dag_fixture(%{name: "other_dag"})
      runs!(dag, [:succeeded, :succeeded])
      runs!(other_dag, [:succeeded, :succeeded])

      assert 1 == Pruner.prune(dag.id, 1)
      assert 2 == length(run_ids(other_dag))
    end

    test "cascades to tasks and logs of deleted runs" do
      dag = dag_fixture()
      [old_run, _new_run] = runs!(dag, [:succeeded, :succeeded])
      task = task_fixture(%{run_id: old_run.id, name: "my_task"})
      log_fixture(%{task_id: task.id, content: "hello", level: "info", attempt: 1})

      assert 1 == Pruner.prune(dag.id, 1)
      assert nil == Repo.get(Task, task.id)
      assert [] == Repo.all(from l in Log, where: l.task_id == ^task.id)
    end

    test "deletes in batches and broadcasts each one" do
      dag = dag_fixture()

      [first_batch, second_batch] =
        dag
        |> runs!(List.duplicate(:succeeded, 5))
        |> Enum.take(4)
        |> Enum.map(& &1.id)
        |> Enum.chunk_every(3)

      Gust.PubSub.subscribe_runs_for_dag(dag.id)
      dag_id = dag.id

      assert 4 == Pruner.prune(dag.id, 1, batch_size: 3)

      assert_receive {:dag, :runs_pruned, %{dag_id: ^dag_id, run_ids: ^first_batch}}
      assert_receive {:dag, :runs_pruned, %{dag_id: ^dag_id, run_ids: ^second_batch}}
      refute_receive {:dag, :runs_pruned, _payload}, 50
    end

    test "dry_run counts without deleting" do
      dag = dag_fixture()
      runs!(dag, [:succeeded, :failed, :running, :succeeded])
      Gust.PubSub.subscribe_runs_for_dag(dag.id)

      assert 2 == Pruner.prune(dag.id, 1, dry_run: true)
      assert 4 == length(run_ids(dag))
      refute_receive {:dag, :runs_pruned, _payload}, 50
    end
  end

  describe "prune_all/0" do
    test "prunes only dags that set a retention" do
      dag = dag_fixture()
      no_retention_dag = dag_fixture(%{name: "no_retention_dag"})
      runs!(dag, [:succeeded, :succeeded, :succeeded])
      runs!(no_retention_dag, [:succeeded, :succeeded, :succeeded])

      expect(Gust.DAGLoaderMock, :get_definitions, fn ->
        %{
          dag.id =>
            {:ok, %Definition{name: dag.name, options: [runs: [retention: [max_count: 1]]]}},
          no_retention_dag.id => {:ok, %Definition{name: no_retention_dag.name, options: []}}
        }
      end)

      assert %{dag.name => 2} == Pruner.prune_all()
      assert 1 == length(run_ids(dag))
      assert 3 == length(run_ids(no_retention_dag))
    end
  end

  describe "Flows.delete_prunable_runs/3" do
    test "returns no ids when nothing is prunable" do
      dag = dag_fixture()
      assert [] == Flows.delete_prunable_runs(dag.id, 1, 10)
    end
  end

  describe "schedule/0" do
    test "is disabled without prune_schedule" do
      replace_env(:runs, [])
      assert :disabled == Pruner.schedule()
    end

    test "parses crontab expressions and shortcuts" do
      for expression <- ["* * * * *", "0 3 * * *", "@daily", "@hourly", "@minutely"] do
        replace_env(:runs, prune_schedule: expression)
        assert {:ok, %Crontab.CronExpression{}} = Pruner.schedule()
      end
    end

    test "rejects invalid expressions, @reboot and non-strings" do
      for expression <- ["nope", "@reboot", :daily] do
        replace_env(:runs, prune_schedule: expression)
        assert {:error, _reason} = Pruner.schedule()
      end
    end
  end
end
