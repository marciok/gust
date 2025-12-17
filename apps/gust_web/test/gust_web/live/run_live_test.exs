defmodule GustWeb.RunLiveTest do
  alias Gust.Flows
  use GustWeb.ConnCase

  import Phoenix.LiveViewTest
  import Gust.FlowsFixtures
  import Mox

  setup :verify_on_exit!

  describe "Index" do
    setup %{conn: conn} do
      dag = dag_fixture(%{name: "dag_with_runs"})
      run = run_fixture(%{dag_id: dag.id})

      %{conn: conn, run: run, dag: dag}
    end

    test "list runs", %{conn: conn, dag: dag, run: run} do
      {:ok, _index_live, html} =
        live(conn, ~p"/dags/#{dag.name}/runs?page_size=30&page=1")

      assert html =~ "Listing Runs"
      assert html =~ dag.name
      assert html =~ to_string(run.status)
      assert html =~ to_string(run.inserted_at)
      assert html =~ to_string(run.updated_at)
      assert html =~ to_string(run.id)
    end

    test "list runs paged", %{conn: conn, dag: dag, run: _first_run} do
      page_size = 3

      run_fixture(%{dag_id: dag.id})
      prev_page_run = run_fixture(%{dag_id: dag.id})

      current_page_run = run_fixture(%{dag_id: dag.id})

      {:ok, index_live, _html} =
        live(conn, ~p"/dags/#{dag.name}/runs?page_size=#{page_size}&page=2")

      assert index_live |> has_element?("#runs-#{current_page_run.id}")
      refute index_live |> has_element?("#runs-#{prev_page_run.id}")

      assert index_live |> has_element?("#pages option[value='2']:checked")
      refute index_live |> has_element?("#pages option[value='3']")

      index_live
      |> element("#page-select")
      |> render_change(%{"_target" => "page", "page" => "1"})

      assert_patch index_live, ~p"/dags/#{dag.name}/runs?page_size=3&page=1"
    end

    test "deletes run in listing", %{conn: conn, dag: dag, run: run} do
      {:ok, index_live, _html} = live(conn, ~p"/dags/#{dag.name}/runs?page_size=30&page=1")

      assert index_live |> element("#runs-#{run.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#runs-#{run.id}")
    end

    test "new dag run was created", %{conn: conn, dag: dag} do
      {:ok, index_live, _html} =
        live(conn, ~p"/dags/#{dag.name}/runs?page_size=30&page=1")

      new_run = run_fixture(%{dag_id: dag.id})

      Gust.PubSub.broadcast_run_started(dag.id, new_run.id)

      assert index_live |> has_element?("#runs-#{new_run.id}")
    end

    test "run is updated", %{conn: conn, dag: dag, run: run} do
      {:ok, index_live, _html} =
        live(conn, ~p"/dags/#{dag.name}/runs?page_size=30&page=1")

      Flows.update_run_status(run, :succeeded)

      Gust.PubSub.broadcast_run_status(run.id, :succeeded)

      badge_html =
        index_live |> element("#runs-#{run.id} [data-testid='status-badge']") |> render()

      assert badge_html =~ "succeeded"
    end
  end
end
