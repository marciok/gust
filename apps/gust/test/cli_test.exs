defmodule Gust.CLITest do
  use Gust.DataCase
  import ExUnit.CaptureLog

  import Gust.FlowsFixtures
  import Mox

  alias Gust.CLI
  alias Gust.Flows

  setup :verify_on_exit!
  setup :set_mox_from_context

  setup do
    dag = dag_fixture(%{name: "cli_test_dag"})
    dag_id = dag.id

    %{dag_name: dag.name, dag_id: dag_id}
  end

  test "exec/1 triggers a run for a named dag", %{dag_name: dag_name, dag_id: dag_id} do
    Gust.DAGRunTriggerMock
    |> expect(:dispatch_run, fn %Flows.Run{dag_id: ^dag_id} = run ->
      run
    end)

    {json, log} =
      with_log(fn ->
        CLI.exec(["trigger_run", dag_name])
      end)

    [last_run] = Flows.get_dag_with_runs!(dag_id).runs

    assert log =~ "Triggered DAG cli_test_dag; Run: #{last_run.id}"
    assert %{"status" => "ok", "run_id" => run_id} = Jason.decode!(json)
    assert run_id == last_run.id
    assert %Flows.Run{params: %{}} = last_run
  end

  test "exec/1 triggers a run with --run_params", %{
    dag_name: dag_name,
    dag_id: dag_id
  } do
    Gust.DAGRunTriggerMock
    |> expect(:dispatch_run, fn %Flows.Run{dag_id: ^dag_id} = run ->
      run
    end)

    with_log(fn ->
      CLI.exec(["trigger_run", dag_name, "--run_params", ~s({"name": "foo"})])
    end)

    [last_run] = Flows.get_dag_with_runs!(dag_id).runs
    assert %Flows.Run{params: %{"name" => "foo"}} = last_run
  end

  test "exec/1 get dag definition for a name that is not a dag", %{
    dag_name: _dag_name,
    dag_id: _dag_id
  } do
    not_a_dag_name = "not_a_dag_name"

    assert_raise(RuntimeError, "There are no DAGs with name: #{not_a_dag_name}", fn ->
      CLI.exec(["dag_definition", not_a_dag_name])
    end)
  end

  test "exec/1 get dag definition for a named dag", %{dag_name: dag_name, dag_id: dag_id} do
    dag_def = %Gust.DAG.Definition{
      name: dag_name,
      tasks: %{
        "hello" => %{
          downstream: MapSet.new(["say_bye"]),
          upstream: MapSet.new()
        }
      }
    }

    Gust.DAGLoaderMock
    |> expect(:get_definition, fn ^dag_id ->
      {:ok, dag_def}
    end)

    assert %{
             "status" => "ok",
             "definition" => %{
               "name" => ^dag_name,
               "tasks" => %{
                 "hello" => %{"downstream" => ["say_bye"], "upstream" => []}
               }
             }
           } = CLI.exec(["dag_definition", dag_name]) |> Jason.decode!()
  end

  test "exec/1 returns definition status when loading the dag definition fails", %{
    dag_name: dag_name,
    dag_id: dag_id
  } do
    error = {[line: 9], "parsing error", "unexpected token"}

    Gust.DAGLoaderMock
    |> expect(:get_definition, fn ^dag_id ->
      {:error, error}
    end)

    assert %{
             "status" => "error",
             "error" => "{[line: 9], \"parsing error\", \"unexpected token\"}"
           } = CLI.exec(["dag_definition", dag_name]) |> Jason.decode!()
  end

  describe "exec/1 prune_runs" do
    setup %{dag_id: dag_id} do
      for status <- [:succeeded, :failed, :succeeded, :running] do
        run_fixture(%{dag_id: dag_id, status: status})
      end

      :ok
    end

    test "keeps the given number of finished runs", %{dag_name: dag_name, dag_id: dag_id} do
      assert %{
               "status" => "ok",
               "dag_name" => ^dag_name,
               "max_count" => 1,
               "dry_run" => false,
               "pruned" => 2
             } = CLI.exec(["prune_runs", dag_name, "--max-count", "1"]) |> Jason.decode!()

      assert 2 == Flows.count_runs_on_dag(dag_id)
      assert 1 == Flows.count_runs_on_dag(dag_id, :running)
    end

    test "--dry-run reports counts without deleting", %{dag_name: dag_name, dag_id: dag_id} do
      assert %{"status" => "ok", "dry_run" => true, "pruned" => 2} =
               CLI.exec(["prune_runs", dag_name, "--max-count", "1", "--dry-run"])
               |> Jason.decode!()

      assert 4 == Flows.count_runs_on_dag(dag_id)
    end

    test "returns usage without a dag name or a positive --max-count", %{
      dag_name: dag_name,
      dag_id: dag_id
    } do
      for args <- [[dag_name], ["--max-count", "1"], [dag_name, "--max-count", "0"]] do
        assert %{"status" => "error", "error" => "usage: prune_runs" <> _rest} =
                 CLI.exec(["prune_runs" | args]) |> Jason.decode!()
      end

      assert 4 == Flows.count_runs_on_dag(dag_id)
    end

    test "raises for an unknown dag" do
      assert_raise RuntimeError, "There are no DAGs with name: nope", fn ->
        CLI.exec(["prune_runs", "nope", "--max-count", "1"])
      end
    end
  end
end
