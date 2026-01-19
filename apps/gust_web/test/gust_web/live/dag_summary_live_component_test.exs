# TODO: test schedule change
defmodule GustWeb.DagSummaryLiveComponentTest do
  use GustWeb.ConnCase
  import Phoenix.LiveViewTest
  import Gust.FlowsFixtures
  alias Gust.Flows

  require GustWeb.LiveComponentTest
  import GustWeb.LiveComponentTest
  import Mox

  setup :verify_on_exit!

  setup do
    dag = dag_fixture(%{name: "my_dag"})
    Gust.Flows.get_dag!(dag.id)

    dag_def = %Gust.DAG.Definition{
      name: "my_dag",
      options: [schedule: "* * * *"]
    }

    %{dag: dag, dag_def: dag_def}
  end

  describe "when dag_define has error" do
    test "cannot be triggered", %{conn: conn, dag: dag, dag_def: dag_def} do
      error_description = "Ops, something went kaboom"
      message = "check your code!"

      dag_def = %{
        dag_def
        | messages: [%{message: message}],
          error: %CompileError{description: error_description}
      }

      {:ok, dag_summary, html} =
        live_component_isolated(conn, GustWeb.DagSummaryComponent, %{
          id: dag.id,
          dag: dag,
          dag_def: dag_def
        })

      assert dag_summary |> has_element?("#trigger-dag-run-#{dag.id}:disabled")

      assert html =~ error_description
      assert html =~ message
    end
  end

  test "re-enabled dag", %{conn: conn, dag: dag, dag_def: dag_def} do
    dag_id = dag.id
    {:ok, dag} = Flows.toggle_enabled(dag)

    GustWeb.DAGRunTriggerMock |> expect(:dispatch_all_runs, fn ^dag_id -> nil end)

    {:ok, dag_summary, _html} =
      live_component_isolated(conn, GustWeb.DagSummaryComponent, %{
        id: dag_id,
        dag: dag,
        dag_def: dag_def
      })

    dag_summary |> element("[name='dag-enabling-toggle-#{dag.id}']") |> render_click()

    assert Gust.Flows.get_dag!(dag.id).enabled == true
  end

  test "toggle dag enabled", %{conn: conn, dag: dag, dag_def: dag_def} do
    dag_id = dag.id

    {:ok, dag_summary, _html} =
      live_component_isolated(conn, GustWeb.DagSummaryComponent, %{
        id: dag_id,
        dag: dag,
        dag_def: dag_def
      })

    dag_summary |> element("[name='dag-enabling-toggle-#{dag.id}']:checked") |> render_click()

    assert Gust.Flows.get_dag!(dag.id).enabled == false
  end

  test "link to dag runs", %{conn: conn, dag: dag, dag_def: dag_def} do
    {:ok, dag_summary, _html} =
      live_component_isolated(conn, GustWeb.DagSummaryComponent, %{
        dag: dag,
        dag_def: dag_def
      })

    assert dag_summary |> has_element?(~s{[href="/dags/#{dag.name}/dashboard"]})
    dag_summary |> element(~s{[href="/dags/#{dag.name}/dashboard"]}) |> render_click()

    assert_redirect dag_summary, "/dags/#{dag.name}/dashboard"
  end
end
