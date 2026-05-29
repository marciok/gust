defmodule GustWeb.APIController do
  use GustWeb, :controller

  alias Gust.DAG.Run.Trigger
  alias Gust.Flows

  plug(GustWeb.Plugs.APIAuth)

  def create_run(conn, %{"dag_name" => dag_name} = params) do
    dag = Flows.get_dag_by_name(dag_name)
    run_params = Map.get(params, "params", %{})

    {status, payload} =
      if dag do
        {:ok, run} = Flows.create_run(%{dag_id: dag.id, params: run_params})
        run = Trigger.dispatch_run(run)

        {:created, %{id: to_string(run.id), status: to_string(run.status)}}
      else
        {:not_found, %{error: "dag_not_found"}}
      end

    conn
    |> put_status(status)
    |> json(payload)
  end
end
