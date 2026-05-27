defmodule Mix.Tasks.Gust.CliTest do
  use Gust.DataCase

  alias Mix.Tasks.Gust.Cli, as: GustCli

  import Gust.FlowsFixtures
  import ExUnit.CaptureLog
  import Mox

  setup :verify_on_exit!
  setup :set_mox_from_context

  setup do
    Mix.shell(Mix.Shell.Process)
    Mix.Task.reenable("gust.cli")

    old_role = System.get_env("GUST_ROLE")

    on_exit(fn ->
      Mix.shell(Mix.Shell.IO)

      if old_role do
        System.put_env("GUST_ROLE", old_role)
      else
        System.delete_env("GUST_ROLE")
      end
    end)

    dag = dag_fixture(%{name: "marcio"})

    %{dag: dag}
  end

  test "prints dag definition json and defaults the role to console", %{dag: dag} do
    dag_def = %Gust.DAG.Definition{name: dag.name}
    dag_id = dag.id

    Gust.DAGLoaderMock
    |> expect(:get_definition, fn ^dag_id ->
      {:ok, dag_def}
    end)

    System.delete_env("GUST_ROLE")

    with_log(fn ->
      GustCli.run(["dag_definition", dag.name])
    end)

    assert_received {:mix_shell, :info, [json]}
    assert System.get_env("GUST_ROLE") == "console"

    assert %{
             "status" => "ok",
             "definition" => %{"name" => "marcio"}
           } = Jason.decode!(json)
  end
end
