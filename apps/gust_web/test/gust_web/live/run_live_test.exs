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
        live(conn, ~g"/dags/#{dag.name}/runs?page_size=30&page=1")

      formats = Application.get_env(:gust_web, :display_date_format)
      run_inserted_at = Calendar.strftime(run.inserted_at, formats[:long])
      run_updated_at = Calendar.strftime(run.updated_at, formats[:long])

      assert html =~ "Listing Runs"
      assert html =~ dag.name
      assert html =~ to_string(run.status)
      assert html =~ run_inserted_at
      assert html =~ run_updated_at
      assert html =~ to_string(run.id)
    end

    test "list runs with params", %{conn: conn, dag: dag} do
      _run = run_fixture(%{dag_id: dag.id, params: %{"my_key" => "my_value"}})

      {:ok, _index_live, html} =
        live(conn, ~g"/dags/#{dag.name}/runs?page_size=30&page=1")

      assert html =~ "Params"
      assert html =~ "my_key"
      assert html =~ "my_value"
    end

    test "list runs paged", %{conn: conn, dag: dag, run: _first_run} do
      page_size = 3

      run_fixture(%{dag_id: dag.id})
      prev_page_run = run_fixture(%{dag_id: dag.id})

      current_page_run = run_fixture(%{dag_id: dag.id})

      {:ok, index_live, _html} =
        live(conn, ~g"/dags/#{dag.name}/runs?page_size=#{page_size}&page=2")

      assert index_live |> has_element?("#runs-#{current_page_run.id}")
      refute index_live |> has_element?("#runs-#{prev_page_run.id}")

      assert index_live |> has_element?("#pages option[value='2']:checked")
      refute index_live |> has_element?("#pages option[value='3']")

      index_live
      |> element("#page-select")
      |> render_change(%{"_target" => "page", "page" => "1"})

      assert_patch index_live, ~g"/dags/#{dag.name}/runs?page_size=3&page=1"
    end

    test "filters runs by status", %{conn: conn, dag: dag, run: created_run} do
      failed_run = run_fixture(%{dag_id: dag.id, status: :failed})
      succeeded_run = run_fixture(%{dag_id: dag.id, status: :succeeded})

      {:ok, index_live, _html} =
        live(conn, ~g"/dags/#{dag.name}/runs?page_size=30&page=1")

      index_live
      |> element("#status-filter")
      |> render_change(%{"_target" => "status", "status" => "failed"})

      assert_patch index_live, ~g"/dags/#{dag.name}/runs?page_size=30&page=1&status=failed"
      assert index_live |> has_element?("#run-status-filter option[value='failed']:checked")
      assert index_live |> has_element?("#runs-#{failed_run.id}")
      refute index_live |> has_element?("#runs-#{created_run.id}")
      refute index_live |> has_element?("#runs-#{succeeded_run.id}")
    end

    test "clears status filter", %{conn: conn, dag: dag, run: created_run} do
      failed_run = run_fixture(%{dag_id: dag.id, status: :failed})

      {:ok, index_live, _html} =
        live(conn, ~g"/dags/#{dag.name}/runs?page_size=30&page=1&status=failed")

      index_live
      |> element("#status-filter")
      |> render_change(%{"_target" => "status", "status" => ""})

      assert_patch index_live, ~g"/dags/#{dag.name}/runs?page_size=30&page=1"
      assert index_live |> has_element?("#runs-#{created_run.id}")
      assert index_live |> has_element?("#runs-#{failed_run.id}")
    end

    test "treats empty status params as all statuses", %{conn: conn, dag: dag, run: created_run} do
      failed_run = run_fixture(%{dag_id: dag.id, status: :failed})

      {:ok, index_live, _html} =
        live(conn, ~g"/dags/#{dag.name}/runs?page_size=30&page=1&status=")

      assert index_live |> has_element?("#run-status-filter option[value='']:checked")
      assert index_live |> has_element?("#runs-#{created_run.id}")
      assert index_live |> has_element?("#runs-#{failed_run.id}")
    end

    test "treats unknown status params as all statuses", %{conn: conn, dag: dag, run: created_run} do
      failed_run = run_fixture(%{dag_id: dag.id, status: :failed})

      {:ok, index_live, _html} =
        live(conn, ~g"/dags/#{dag.name}/runs?page_size=30&page=1&status=not_a_status")

      assert index_live |> has_element?("#run-status-filter option[value='']:checked")
      assert index_live |> has_element?("#runs-#{created_run.id}")
      assert index_live |> has_element?("#runs-#{failed_run.id}")
    end

    test "keeps status filter when selecting page", %{conn: conn, dag: dag, run: _first_run} do
      page_size = 1
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      older_failed_run =
        run_fixture(%{dag_id: dag.id, status: :failed, inserted_at: DateTime.add(now, -60)})

      newer_failed_run =
        run_fixture(%{dag_id: dag.id, status: :failed, inserted_at: DateTime.add(now, 60)})

      _created_run = run_fixture(%{dag_id: dag.id, status: :created})

      {:ok, index_live, _html} =
        live(conn, ~g"/dags/#{dag.name}/runs?page_size=#{page_size}&page=1&status=failed")

      assert index_live |> has_element?("#runs-#{newer_failed_run.id}")
      refute index_live |> has_element?("#runs-#{older_failed_run.id}")

      index_live
      |> element("#page-select")
      |> render_change(%{"_target" => "page", "page" => "2"})

      assert_patch index_live, ~g"/dags/#{dag.name}/runs?page_size=1&page=2&status=failed"
    end

    test "deletes run in listing", %{conn: conn, dag: dag, run: run} do
      {:ok, index_live, _html} = live(conn, ~g"/dags/#{dag.name}/runs?page_size=30&page=1")

      assert index_live |> element("#runs-#{run.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#runs-#{run.id}")
    end

    test "batch deletes selected runs in listing", %{conn: conn, dag: dag, run: first_run} do
      second_run = run_fixture(%{dag_id: dag.id})
      kept_run = run_fixture(%{dag_id: dag.id})
      other_dag = dag_fixture(%{name: "other_dag_with_runs"})
      other_dag_run = run_fixture(%{dag_id: other_dag.id})

      {:ok, index_live, _html} = live(conn, ~g"/dags/#{dag.name}/runs?page_size=30&page=1")

      selected_params = %{"run_ids" => [to_string(first_run.id), to_string(second_run.id)]}

      index_live
      |> element("#run-batch-form")
      |> render_change(selected_params)

      assert index_live
             |> element("#batch-delete-runs")
             |> render_click()

      refute has_element?(index_live, "#runs-#{first_run.id}")
      refute has_element?(index_live, "#runs-#{second_run.id}")
      assert has_element?(index_live, "#runs-#{kept_run.id}")
      assert Flows.get_run!(kept_run.id)
      assert Flows.get_run!(other_dag_run.id)
      assert_raise Ecto.NoResultsError, fn -> Flows.get_run!(first_run.id) end
      assert_raise Ecto.NoResultsError, fn -> Flows.get_run!(second_run.id) end
    end

    test "batch delete with no selected runs does nothing", %{conn: conn, dag: dag, run: run} do
      {:ok, index_live, _html} = live(conn, ~g"/dags/#{dag.name}/runs?page_size=30&page=1")

      assert has_element?(index_live, "#batch-delete-runs[disabled]")

      refute render_click(index_live, "batch_delete", %{}) =~ "runs deleted"

      assert has_element?(index_live, "#runs-#{run.id}")
      assert Flows.get_run!(run.id)
    end

    test "batch restarts selected runs in listing", %{conn: conn, dag: dag, run: first_run} do
      second_run = run_fixture(%{dag_id: dag.id})
      other_dag = dag_fixture(%{name: "other_dag_with_restart_run"})
      other_dag_run = run_fixture(%{dag_id: other_dag.id})
      parent = self()

      GustWeb.DAGRunTriggerMock
      |> expect(:reset_run, 2, fn %Flows.Run{dag_id: dag_id} = run ->
        assert dag_id == dag.id
        send(parent, {:restarted_run, run.id})
        run
      end)

      {:ok, index_live, _html} = live(conn, ~g"/dags/#{dag.name}/runs?page_size=30&page=1")

      selected_params = %{
        "run_ids" => [
          to_string(first_run.id),
          to_string(second_run.id),
          to_string(other_dag_run.id)
        ]
      }

      index_live
      |> element("#run-batch-form")
      |> render_change(selected_params)

      assert index_live
             |> element("#batch-restart-runs")
             |> render_click() =~ "2 runs restarted"

      first_run_id = first_run.id
      second_run_id = second_run.id
      other_dag_run_id = other_dag_run.id

      assert_received {:restarted_run, ^first_run_id}
      assert_received {:restarted_run, ^second_run_id}
      refute_received {:restarted_run, ^other_dag_run_id}
    end

    test "batch restart with no selected runs does nothing", %{conn: conn, dag: dag, run: run} do
      {:ok, index_live, _html} = live(conn, ~g"/dags/#{dag.name}/runs?page_size=30&page=1")

      assert has_element?(index_live, "#batch-restart-runs[disabled]")

      refute render_click(index_live, "batch_restart", %{}) =~ "runs restarted"

      assert has_element?(index_live, "#runs-#{run.id}")
      assert Flows.get_run!(run.id)
    end

    test "selects all visible runs for batch delete", %{conn: conn, dag: dag, run: first_run} do
      second_run = run_fixture(%{dag_id: dag.id})
      third_run = run_fixture(%{dag_id: dag.id})

      {:ok, index_live, _html} = live(conn, ~g"/dags/#{dag.name}/runs?page_size=30&page=1")

      index_live
      |> element("#select-all-runs")
      |> render_click()

      assert has_element?(index_live, "#select-all-runs[checked]")
      assert has_element?(index_live, "#run-select-#{first_run.id}[checked]")
      assert has_element?(index_live, "#run-select-#{second_run.id}[checked]")
      assert has_element?(index_live, "#run-select-#{third_run.id}[checked]")

      assert index_live
             |> element("#batch-delete-runs")
             |> render_click()

      refute has_element?(index_live, "#runs-#{first_run.id}")
      refute has_element?(index_live, "#runs-#{second_run.id}")
      refute has_element?(index_live, "#runs-#{third_run.id}")
      assert_raise Ecto.NoResultsError, fn -> Flows.get_run!(first_run.id) end
      assert_raise Ecto.NoResultsError, fn -> Flows.get_run!(second_run.id) end
      assert_raise Ecto.NoResultsError, fn -> Flows.get_run!(third_run.id) end
    end

    test "new dag run was created", %{conn: conn, dag: dag} do
      {:ok, index_live, _html} =
        live(conn, ~g"/dags/#{dag.name}/runs?page_size=30&page=1")

      new_run = run_fixture(%{dag_id: dag.id})

      Gust.PubSub.broadcast_run_started(dag.id, new_run.id)

      assert index_live |> has_element?("#runs-#{new_run.id}")
    end

    test "does not insert newly started runs outside the selected status", %{conn: conn, dag: dag} do
      {:ok, index_live, _html} =
        live(conn, ~g"/dags/#{dag.name}/runs?page_size=30&page=1&status=failed")

      new_run = run_fixture(%{dag_id: dag.id, status: :created})

      Gust.PubSub.broadcast_run_started(dag.id, new_run.id)

      refute index_live |> has_element?("#runs-#{new_run.id}")
    end

    test "run is updated", %{conn: conn, dag: dag, run: run} do
      {:ok, index_live, _html} =
        live(conn, ~g"/dags/#{dag.name}/runs?page_size=30&page=1")

      Flows.update_run_status(run, :succeeded)

      Gust.PubSub.broadcast_run_status(run.id, :succeeded)

      badge_html =
        index_live |> element("#runs-#{run.id} [data-testid='status-badge']") |> render()

      assert badge_html =~ "succeeded"
    end

    test "updates runs that still match the selected status", %{conn: conn, dag: dag} do
      failed_run = run_fixture(%{dag_id: dag.id, status: :failed})

      {:ok, index_live, _html} =
        live(conn, ~g"/dags/#{dag.name}/runs?page_size=30&page=1&status=failed")

      Gust.PubSub.broadcast_run_status(failed_run.id, :failed)

      assert index_live |> has_element?("#runs-#{failed_run.id}")
    end

    test "removes updated runs that no longer match the selected status", %{conn: conn, dag: dag} do
      failed_run = run_fixture(%{dag_id: dag.id, status: :failed})

      {:ok, index_live, _html} =
        live(conn, ~g"/dags/#{dag.name}/runs?page_size=30&page=1&status=failed")

      assert index_live |> has_element?("#runs-#{failed_run.id}")

      Flows.update_run_status(failed_run, :succeeded)
      Gust.PubSub.broadcast_run_status(failed_run.id, :succeeded)

      refute index_live |> has_element?("#runs-#{failed_run.id}")
    end
  end
end
