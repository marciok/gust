defmodule GustWeb.APIController do
  use GustWeb, :controller

  alias Gust.DAG.Run.Trigger
  alias Gust.DAG.TaskWaiter
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

  def resume_task(conn, %{"waiting_for" => waiting_for} = params) do
    opts =
      []
      |> maybe_put_run_id(params)
      |> Keyword.put(:payload, Map.get(params, "payload", %{}))

    {:ok, tasks} = TaskWaiter.resume(waiting_for, opts)

    conn
    |> put_status(:ok)
    |> json(Enum.map(tasks, &task_json/1))
  end

  defp maybe_put_run_id(opts, %{"run_id" => run_id}), do: Keyword.put(opts, :run_id, run_id)
  defp maybe_put_run_id(opts, _params), do: opts

  defp task_json(task) do
    %{
      id: to_string(task.id),
      run_id: to_string(task.run_id),
      name: task.name,
      status: to_string(task.status),
      params: task.params,
      result: task.result,
      error: task.error,
      waiting_for: task.waiting_for,
      wait_satisfied_at: task.wait_satisfied_at,
      attempt: task.attempt,
      map_index: task.map_index
    }
  end
end
