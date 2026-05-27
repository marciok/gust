defmodule GustWeb.APIController do
  use GustWeb, :controller

  alias Gust.Flows

  plug(GustWeb.Plugs.APIAuth)

  def create_run(conn, %{"dag_name" => dag_name}) do
    dag = Flows.get_dag_by_name(dag_name)

    {status, payload} =
      if dag do
        {:ok, run} = Flows.create_run(%{dag_id: dag.id, status: :enqueued})

        {:created, %{id: to_string(run.id), status: to_string(run.status)}}
      else
        {:not_found, %{error: "dag_not_found"}}
      end

    conn
    |> put_status(status)
    |> json(payload)
  end
end
