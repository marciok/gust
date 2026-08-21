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
      successful_dag = dag_fixture(%{name: "successful_dag"})
      broken_dag = dag_fixture(%{name: "broken_dag"})

      dag_def = %Gust.DAG.Definition{name: dag.name}
      successful_dag_def = %Gust.DAG.Definition{name: successful_dag.name}

      dag_defs = %{
        dag.id => {:ok, dag_def},
        successful_dag.id => {:ok, successful_dag_def},
        broken_dag.id => {:error, {}}
      }

      GustWeb.DAGLoaderMock
      |> expect(:get_definitions, 2, fn ->
        dag_defs
      end)

      %{
        conn: conn,
        dag: dag,
        dag_def: dag_def,
        dag_defs: dag_defs,
        successful_dag: successful_dag,
        broken_dag: broken_dag
      }
    end

    test "lists all valid dags on dag folder", %{conn: conn, dag: dag, broken_dag: broken_dag} do
      {:ok, _index_live, html} = live(conn, ~g"/dags")

      assert html =~ "DAGs Listing"
      assert html =~ dag.name
      assert html =~ broken_dag.name
    end

    test "shows the statuses of the ten most recent runs", %{conn: conn, dag: dag} do
      runs =
        for index <- 1..12 do
          status = if rem(index, 2) == 0, do: :succeeded, else: :failed

          run_fixture(%{
            dag_id: dag.id,
            status: status,
            inserted_at: NaiveDateTime.add(~N[2024-01-01 00:00:00], index, :day)
          })
        end

      {:ok, index_live, _html} = live(conn, ~g"/dags")

      assert has_element?(index_live, "#dag-run-history-#{dag.id}")

      runs
      |> Enum.drop(2)
      |> Enum.each(fn run ->
        assert has_element?(index_live, "#dag-#{dag.id}-run-#{run.id}.status-#{run.status}")
      end)

      runs
      |> Enum.take(2)
      |> Enum.each(fn run ->
        refute has_element?(index_live, "#dag-#{dag.id}-run-#{run.id}")
      end)
    end

    test "filters dags to those with a failed recent run", %{
      conn: conn,
      dag: dag,
      dag_defs: dag_defs,
      successful_dag: successful_dag
    } do
      _failed_run = run_fixture(%{dag_id: dag.id, status: :failed})
      _successful_run = run_fixture(%{dag_id: successful_dag.id, status: :succeeded})

      {:ok, index_live, _html} = live(conn, ~g"/dags")

      assert has_element?(index_live, "#dag-index-header")

      assert has_element?(
               index_live,
               "#dag-index-header [data-slot='header-actions'] #dag-filter-form"
             )

      assert has_element?(index_live, "#recent-failures-only:not(:checked)")
      assert has_element?(index_live, "#dag-run-history-#{dag.id}")
      assert has_element?(index_live, "#dag-run-history-#{successful_dag.id}")

      GustWeb.DAGLoaderMock
      |> expect(:get_definitions, fn -> dag_defs end)

      index_live
      |> form("#dag-filter-form", filters: %{failed_runs_only: "true"})
      |> render_change()

      assert has_element?(index_live, "#recent-failures-only:checked")
      assert has_element?(index_live, "#dag-run-history-#{dag.id}")
      refute has_element?(index_live, "#dag-run-history-#{successful_dag.id}")

      GustWeb.DAGLoaderMock
      |> expect(:get_definitions, fn -> dag_defs end)

      index_live
      |> form("#dag-filter-form", filters: %{failed_runs_only: "false"})
      |> render_change()

      assert has_element?(index_live, "#recent-failures-only:not(:checked)")
      assert has_element?(index_live, "#dag-run-history-#{dag.id}")
      assert has_element?(index_live, "#dag-run-history-#{successful_dag.id}")
    end

    test "shows a reloaded dag with failed recent runs when the filter is active", %{
      conn: conn,
      broken_dag: broken_dag,
      dag_defs: dag_defs
    } do
      failed_run = run_fixture(%{dag_id: broken_dag.id, status: :failed})
      {:ok, index_live, _html} = live(conn, ~g"/dags")

      GustWeb.DAGLoaderMock
      |> expect(:get_definitions, fn -> dag_defs end)

      index_live
      |> form("#dag-filter-form", filters: %{failed_runs_only: "true"})
      |> render_change()

      assert has_element?(index_live, "#broken-dags > div")
      refute has_element?(index_live, "#dag-run-history-#{broken_dag.id}")

      send(
        index_live.pid,
        {:dag, :file_updated,
         %{
           action: "reload",
           parse_result: {:ok, %Gust.DAG.Definition{name: broken_dag.name}}
         }}
      )

      assert has_element?(index_live, "#dag-run-history-#{broken_dag.id}")
      assert has_element?(index_live, "#dag-#{broken_dag.id}-run-#{failed_run.id}.status-failed")
      refute has_element?(index_live, "#broken-dags > div")
    end

    test "keeps a reloaded dag hidden when it has no failed recent runs", %{
      conn: conn,
      dag: dag,
      dag_defs: dag_defs,
      successful_dag: successful_dag
    } do
      _failed_run = run_fixture(%{dag_id: dag.id, status: :failed})
      _successful_run = run_fixture(%{dag_id: successful_dag.id, status: :succeeded})
      {:ok, index_live, _html} = live(conn, ~g"/dags")

      GustWeb.DAGLoaderMock
      |> expect(:get_definitions, fn -> dag_defs end)

      index_live
      |> form("#dag-filter-form", filters: %{failed_runs_only: "true"})
      |> render_change()

      assert has_element?(index_live, "#dag-run-history-#{dag.id}")
      refute has_element?(index_live, "#dag-run-history-#{successful_dag.id}")

      send(
        index_live.pid,
        {:dag, :file_updated,
         %{
           action: "reload",
           parse_result: {:ok, %Gust.DAG.Definition{name: successful_dag.name}}
         }}
      )

      refute has_element?(index_live, "#dag-run-history-#{successful_dag.id}")
    end

    test "dag file was reloaded", %{conn: conn, dag: dag, broken_dag: broken_dag} do
      {:ok, index_live, _html} = live(conn, ~g"/dags")
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
      {:ok, index_live, _html} = live(conn, ~g"/dags")

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
      {:ok, index_live, _html} = live(conn, ~g"/dags")

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
      {:ok, index_live, _html} = live(conn, ~g"/dags")

      assert has_element?(index_live, ~s{[href="/dags/#{dag.name}/dashboard"]})
    end

    test "click on dag run trigger", %{conn: conn, dag: dag} do
      dag_id = dag.id
      {:ok, index_live, _html} = live(conn, ~g"/dags")

      GustWeb.DAGRunTriggerMock |> expect(:dispatch_run, fn new_run -> new_run end)

      triggered_flash = index_live |> element("#trigger-dag-run-#{dag.id}") |> render_click()

      last_run = Flows.get_dag_with_runs!(dag_id).runs |> List.last()

      assert triggered_flash =~ "Run #{last_run.id} triggered"
    end
  end
end
