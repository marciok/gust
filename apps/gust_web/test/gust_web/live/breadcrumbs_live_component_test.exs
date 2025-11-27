defmodule GustWeb.BreadcrumbsLiveComponentTest do
  use GustWeb.ConnCase
  import Phoenix.LiveViewTest
  import Gust.FlowsFixtures

  require GustWeb.LiveComponentTest
  import GustWeb.LiveComponentTest

  setup do
    dag = dag_fixture(%{name: "my_dag"})
    Gust.Flows.get_dag!(dag.id)

    dag_def = %Gust.DAG.Definition{
      name: "my_dag",
      options: [schedule: "* * * *"]
    }

    %{dag: dag, dag_def: dag_def}
  end

  test "only dag is provided", %{conn: conn, dag_def: dag_def} do
    {:ok, breadcrumbs, _html} =
      live_component_isolated(conn, GustWeb.BreadcrumbsComponent, %{
        run: nil,
        task: nil,
        dag_def: dag_def
      })

    assert breadcrumbs |> element("#dag-runs-link") |> render_click()
    assert_redirect breadcrumbs, "/dags/#{dag_def.name}/runs"

    {:ok, breadcrumbs, _html} =
      live_component_isolated(conn, GustWeb.BreadcrumbsComponent, %{
        run: nil,
        task: nil,
        dag_def: dag_def
      })

    assert breadcrumbs |> element("#dags-link") |> render_click()
    assert_redirect breadcrumbs, "/dags"
  end

  test "dag and run is provided", %{conn: conn, dag: dag, dag_def: dag_def} do
    run = run_fixture(%{dag_id: dag.id})

    {:ok, breadcrumbs, _html} =
      live_component_isolated(conn, GustWeb.BreadcrumbsComponent, %{
        run: run,
        task: nil,
        dag_def: dag_def
      })

    assert breadcrumbs |> element("#dag-run-link") |> render_click()
    assert_redirect breadcrumbs, "/dags/#{dag_def.name}/runs?run_id=#{run.id}"
  end

  test "dag, run and task is provided", %{conn: conn, dag: dag, dag_def: dag_def} do
    run = run_fixture(%{dag_id: dag.id})
    task = task_fixture(%{run_id: run.id, name: "hello_breadcrumb"})

    {:ok, breadcrumbs, _html} =
      live_component_isolated(conn, GustWeb.BreadcrumbsComponent, %{
        run: run,
        task: task,
        dag_def: dag_def
      })

    assert breadcrumbs |> element("#dag-run-task-link") |> render_click()

    assert_redirect breadcrumbs,
                    "/dags/#{dag_def.name}/runs?run_id=#{run.id}&task_name=#{task.name}"
  end
end
