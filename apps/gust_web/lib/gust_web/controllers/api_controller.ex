defmodule GustWeb.APIController do
  use GustWeb, :controller

  alias Gust.DAG.Run.Trigger
  alias Gust.Flows

  plug(GustWeb.Plugs.APIAuth)

  def create_run(conn, %{"dag_name" => dag_name}) do
    case Flows.get_dag_by_name(dag_name) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "dag_not_found"})

      dag ->
        {:ok, run} = Flows.create_run(%{dag_id: dag.id})
        run = Trigger.dispatch_run(run)

        conn
        |> put_status(:created)
        |> json(%{id: to_string(run.id)})
    end
  end
end
