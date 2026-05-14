defmodule GustWeb.APIController do
  use GustWeb, :controller

  alias Gust.Flows

  plug(GustWeb.Plugs.APIAuth)

  def create_run(conn, %{"dag_name" => dag_name}) do
    case Flows.get_dag_by_name(dag_name) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "dag_not_found"})

      dag ->
        {:ok, run} = Flows.create_run(%{dag_id: dag.id, status: :enqueued})

        conn
        |> put_status(:created)
        |> json(%{id: to_string(run.id)})
    end
  end
end
