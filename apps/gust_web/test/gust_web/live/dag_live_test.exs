defmodule GustWeb.DagLiveTest do
  alias Gust.Flows
  use GustWeb.ConnCase

  import Phoenix.LiveViewTest
  import Gust.FlowsFixtures
  import Mox

  setup :verify_on_exit!

  describe "Index" do
    setup %{conn: conn} do
      dag = dag_fixture()
      broken_dag = dag_fixture(%{name: "broken_dag"})

      dag_def = %Gust.DAG.Definition{name: dag.name}

      GustWeb.DAGLoaderMock
      |> expect(:get_definitions, 2, fn ->
        %{dag.id => {:ok, dag_def}, broken_dag.id => {:error, {}}}
      end)

      %{conn: conn, dag: dag, dag_def: dag_def, broken_dag: broken_dag}
    end

    test "lists all valid dags on dag folder", %{conn: conn, dag: dag, broken_dag: broken_dag} do
      {:ok, _index_live, html} = live(conn, ~p"/dags")

      assert html =~ "DAGs Listing"
      assert html =~ dag.name
      assert html =~ broken_dag.name
    end

    test "dag file was reloaded", %{conn: conn, dag: dag, broken_dag: broken_dag} do
      {:ok, index_live, _html} = live(conn, ~p"/dags")
      dag_name = dag.name

      dag_def = %Gust.DAG.Definition{name: broken_dag.name}

      send(
        index_live.pid,
        {:dag, :file_updated, %{action: "reload", parse_result: {:ok, dag_def}}}
      )

      broken_dag_html = index_live |> element("#broken-dags") |> render()
      assert render(index_live) =~ dag_name
      refute broken_dag_html =~ broken_dag.name
    end

    test "file reload event when parse errored", %{conn: conn, dag: dag} do
      {:ok, index_live, _html} = live(conn, ~p"/dags")

      dag_name = dag.name

      send(
        index_live.pid,
        {:dag, :file_updated, %{action: "reload", dag_name: dag_name, parse_result: {:error, {}}}}
      )

      Process.sleep(200)
      broken_dag_html = index_live |> element("#broken-dags") |> render()
      dag_html = index_live |> element("#dags") |> render()

      assert broken_dag_html =~ dag.name
      refute dag_html =~ dag.name
    end

    test "file deletion event when a dag exists", %{conn: conn, dag: dag} do
      {:ok, index_live, _html} = live(conn, ~p"/dags")

      dag_name = dag.name
      Flows.delete_dag!(dag)

      send(
        index_live.pid,
        {:dag, :file_updated,
         %{action: "removed", dag_name: dag_name, parse_result: {:error, nil}}}
      )

      refute render(index_live) =~ dag.name
    end

    test "navigate to runs afger click into a dag", %{conn: conn, dag: dag} do
      {:ok, index_live, _html} = live(conn, ~p"/dags")

      assert has_element?(index_live, ~s{[href="/dags/#{dag.name}/runs"]})
    end

    test "click on dag run trigger", %{conn: conn, dag: dag} do
      dag_id = dag.id
      {:ok, index_live, _html} = live(conn, ~p"/dags")

      new_run = run_fixture(%{dag_id: dag_id})

      GustWeb.DAGRunRestarterMock |> expect(:start_dag, fn ^dag_id -> new_run end)

      assert index_live |> element("#trigger-dag-run-#{dag.id}") |> render_click() =~
               "Run #{new_run.id} triggered"
    end
  end
end
