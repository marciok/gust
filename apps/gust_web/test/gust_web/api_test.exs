defmodule GustWeb.APITest do
  use GustWeb.ConnCase

  import Gust.FlowsFixtures
  import Mox

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

  setup :verify_on_exit!
  setup :set_mox_from_context

  describe "gust_api/0" do
    test "defines DAG run creation route inside a scope" do
      paths =
        build_router("/gust/api").__routes__()
        |> Enum.map(& &1.path)

      assert "/gust/api/dags/:dag_name/run" in paths
      assert "/gust/api/tasks/resume" in paths
    end
  end

  describe "POST /api/dags/:dag_name/run" do
    test "creates an enqueued run and returns its id", %{conn: conn} do
      dag = dag_fixture(%{name: "daily_import"})
      dag_id = dag.id
      expect_dispatch_run(dag_id, %{}, :enqueued)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{@token}")
        |> post_api("/api/dags/#{dag.name}/run")

      assert %{"id" => id, "status" => "enqueued"} = json_response(conn, 201)
      assert %Flows.Run{dag_id: ^dag_id, status: :enqueued, params: %{}} = Flows.get_run!(id)
    end

    test "creates an enqueued run with params", %{conn: conn} do
      dag = dag_fixture(%{name: "daily_import_params"})
      dag_id = dag.id
      run_params = %{"name" => "foo"}
      expect_dispatch_run(dag_id, run_params, :enqueued)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{@token}")
        |> post_api("/api/dags/#{dag.name}/run", %{"params" => run_params})

      assert %{"id" => id, "status" => "enqueued"} = json_response(conn, 201)

      assert %Flows.Run{dag_id: ^dag_id, status: :enqueued, params: %{"name" => "foo"}} =
               Flows.get_run!(id)
    end

    test "creates a run without enqueueing when DAG is disabled", %{conn: conn} do
      dag = dag_fixture(%{name: "disabled_import", enabled: false})
      dag_id = dag.id
      expect_dispatch_run(dag_id, %{}, :created)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{@token}")
        |> post_api("/api/dags/#{dag.name}/run")

      assert %{"id" => id, "status" => "created"} = json_response(conn, 201)
      assert %Flows.Run{dag_id: ^dag_id, status: :created} = Flows.get_run!(id)
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

  describe "POST /api/tasks/resume" do
    test "resumes tasks scoped to a run and returns resumed tasks", %{conn: conn} do
      dag = dag_fixture(%{name: "wait_api_dag"})
      run = run_fixture(%{dag_id: dag.id})
      task = task_fixture(%{run_id: run.id, name: "await_payment", status: :created})

      GustWeb.DAGTaskWaiterMock
      |> expect(:resume, fn waiting_for, opts ->
        assert waiting_for == "payment_received"
        assert opts == [payload: %{"invoice_id" => "inv_123"}, run_id: run.id]

        {:ok, [task]}
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{@token}")
        |> post_api("/api/tasks/resume", %{
          "run_id" => run.id,
          "waiting_for" => "payment_received",
          "payload" => %{"invoice_id" => "inv_123"}
        })

      assert [
               %{
                 "id" => task_id,
                 "run_id" => run_id,
                 "name" => "await_payment",
                 "status" => "created",
                 "params" => %{},
                 "result" => %{},
                 "error" => %{},
                 "waiting_for" => nil,
                 "wait_satisfied_at" => nil,
                 "attempt" => 1,
                 "map_index" => nil
               }
             ] = json_response(conn, 200)

      assert task_id == to_string(task.id)
      assert run_id == to_string(run.id)
    end

    test "resumes all tasks waiting on a key when run_id is omitted", %{conn: conn} do
      dag = dag_fixture(%{name: "wait_api_all_dag"})
      first_run = run_fixture(%{dag_id: dag.id})
      second_run = run_fixture(%{dag_id: dag.id})
      first_task = task_fixture(%{run_id: first_run.id, name: "await_first", status: :created})
      second_task = task_fixture(%{run_id: second_run.id, name: "await_second", status: :created})

      GustWeb.DAGTaskWaiterMock
      |> expect(:resume, fn waiting_for, opts ->
        assert waiting_for == "payment_received"
        assert opts == [payload: %{}]
        {:ok, [first_task, second_task]}
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{@token}")
        |> post_api("/api/tasks/resume", %{"waiting_for" => "payment_received"})

      response = json_response(conn, 200)

      assert Enum.map(response, & &1["id"]) == [
               to_string(first_task.id),
               to_string(second_task.id)
             ]

      assert Enum.map(response, & &1["run_id"]) == [
               to_string(first_run.id),
               to_string(second_run.id)
             ]

      assert Enum.map(response, & &1["name"]) == ["await_first", "await_second"]
    end

    test "returns unauthorized without a valid bearer token", %{conn: conn} do
      conn = post_api(conn, "/api/tasks/resume", %{"waiting_for" => "payment_received"})

      assert %{"error" => "unauthorized"} = json_response(conn, 401)
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

  defp post_api(conn, path, body) do
    Phoenix.ConnTest.dispatch(conn, build_router("/api"), :post, path, body)
  end

  defp expect_dispatch_run(dag_id, params, status) do
    GustWeb.DAGRunTriggerMock
    |> expect(:dispatch_run, fn %Flows.Run{dag_id: ^dag_id, params: ^params} = run ->
      {:ok, run} = Flows.update_run_status(run, status)
      run
    end)
  end
end
