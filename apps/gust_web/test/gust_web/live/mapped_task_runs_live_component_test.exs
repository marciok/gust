defmodule GustWeb.MappedTaskRunsLiveComponentTest do
  use GustWeb.ConnCase
  import Phoenix.LiveViewTest
  import Gust.FlowsFixtures

  require GustWeb.LiveComponentTest
  import GustWeb.LiveComponentTest

  setup do
    dag = dag_fixture(%{name: "mapped_task_runs_dag"})
    run = run_fixture(%{dag_id: dag.id})
    task_name = "insert_models"

    succeeded_task =
      task_fixture(%{run_id: run.id, name: task_name, status: :succeeded, map_index: 0})

    failed_task =
      task_fixture(%{run_id: run.id, name: task_name, status: :failed, map_index: 1})

    %{dag: dag, run: run, succeeded_task: succeeded_task, failed_task: failed_task}
  end

  test "renders a row for each mapped task instance", %{
    conn: conn,
    succeeded_task: succeeded_task,
    failed_task: failed_task
  } do
    {:ok, component, _html} =
      live_component_isolated(conn, GustWeb.MappedTaskRunsComponent, %{
        tasks: [succeeded_task, failed_task]
      })

    assert has_element?(component, "#mapped-task-runs")
    assert has_element?(component, "#mapped-task-run-#{succeeded_task.id}")
    assert has_element?(component, "#mapped-task-run-#{failed_task.id}")
    assert render(element(component, "#mapped-task-run-#{succeeded_task.id}")) =~ "succeeded"
    assert render(element(component, "#mapped-task-run-#{failed_task.id}")) =~ "failed"

    assert has_element?(
             component,
             "#show-mapped-task-#{succeeded_task.id}[phx-value-task-id='#{succeeded_task.id}']"
           )
  end

  test "filters task rows by status", %{
    conn: conn,
    succeeded_task: succeeded_task,
    failed_task: failed_task
  } do
    {:ok, component, _html} =
      live_component_isolated(conn, GustWeb.MappedTaskRunsComponent, %{
        tasks: [succeeded_task, failed_task]
      })

    component
    |> element("#mapped-task-status-filter")
    |> render_change(%{"_target" => "status", "status" => "failed"})

    assert has_element?(
             component,
             "#mapped-task-status-filter-select option[value='failed']:checked"
           )

    assert has_element?(component, "#mapped-task-run-#{failed_task.id}")
    refute has_element?(component, "#mapped-task-run-#{succeeded_task.id}")

    component
    |> element("#mapped-task-status-filter")
    |> render_change(%{"_target" => "status", "status" => ""})

    assert has_element?(
             component,
             "#mapped-task-status-filter-select option[value='']:checked"
           )

    assert has_element?(component, "#mapped-task-run-#{succeeded_task.id}")
    assert has_element?(component, "#mapped-task-run-#{failed_task.id}")
  end
end
