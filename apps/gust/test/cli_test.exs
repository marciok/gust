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

    {:ok, log} =
      with_log(fn ->
        CLI.exec(["trigger_run", dag_name])
      end)

    [last_run] = Flows.get_dag_with_runs!(dag_id).runs

    assert log =~ "Triggered DAG cli_test_dag; Run: #{last_run.id}"
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
end
