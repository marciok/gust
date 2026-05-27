defmodule GustWeb.APITest do
  use GustWeb.ConnCase

  import Gust.FlowsFixtures

  alias Gust.Flows

  @token "gust-test-token"

  setup do
    previous_token = Application.get_env(:gust_web, :api_token)

    Application.put_env(:gust_web, :api_token, @token)

    on_exit(fn ->
      if previous_token do
        Application.put_env(:gust_web, :api_token, previous_token)
      else
        Application.delete_env(:gust_web, :api_token)
      end
    end)

    :ok
  end

  describe "gust_api/0" do
    test "defines DAG run creation route inside a scope" do
      paths =
        build_router("/gust/api").__routes__()
        |> Enum.map(& &1.path)

      assert "/gust/api/dags/:dag_name/run" in paths
    end
  end

  describe "POST /api/dags/:dag_name/run" do
    test "creates an enqueued run and returns its id", %{conn: conn} do
      dag = dag_fixture(%{name: "daily_import"})

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{@token}")
        |> post_api("/api/dags/#{dag.name}/run")

      %{"id" => id, "status" => "enqueued"} = json_response(conn, 201)
      run = Flows.get_run!(id)

      assert run.dag_id == dag.id
      assert run.status == :enqueued
    end

    test "creates an enqueued run when DAG is disabled", %{conn: conn} do
      dag = dag_fixture(%{name: "disabled_import", enabled: false})

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{@token}")
        |> post_api("/api/dags/#{dag.name}/run")

      %{"id" => id, "status" => "enqueued"} = json_response(conn, 201)
      run = Flows.get_run!(id)

      assert run.dag_id == dag.id
      assert run.status == :enqueued
    end

    test "returns unauthorized without a valid bearer token", %{conn: conn} do
      dag = dag_fixture(%{name: "daily_import"})

      conn = post_api(conn, "/api/dags/#{dag.name}/run")

      assert %{"error" => "unauthorized"} = json_response(conn, 401)
      assert Flows.count_runs_on_dag(dag.id) == 0
    end

    test "returns not found for an unknown DAG", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{@token}")
        |> post_api("/api/dags/missing/run")

      assert %{"error" => "dag_not_found"} = json_response(conn, 404)
    end
  end

  defp build_router(scope_path) do
    module = Module.concat(__MODULE__, "TestRouter#{System.unique_integer([:positive])}")

    {:module, ^module, _, _} =
      Module.create(
        module,
        quote do
          use Phoenix.Router
          import GustWeb.API

          scope unquote(scope_path) do
            gust_api()
          end
        end,
        Macro.Env.location(__ENV__)
      )

    module
  end

  defp post_api(conn, path) do
    Phoenix.ConnTest.dispatch(conn, build_router("/api"), :post, path, nil)
  end
end
