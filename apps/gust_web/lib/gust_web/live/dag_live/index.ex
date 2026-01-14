defmodule GustWeb.DagLive.Index do
  alias Gust.DAG.{Loader}
  alias Gust.Flows
  alias Gust.PubSub
  alias Gust.DAG.Run.Trigger
  use GustWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    PubSub.subscribe_all_files("update")

    dag_defs = Loader.get_definitions()

    dags =
      for {dag_id, {:ok, dag_def}} <- dag_defs do
        dag = Flows.get_dag!(dag_id)
        %{id: dag.name, dag: dag, dag_def: dag_def}
      end

    broken_dags =
      for {dag_id, {:error, error}} <- dag_defs do
        dag = Flows.get_dag!(dag_id)
        %{id: dag.name, dag: dag, error: error}
      end

    {:ok,
     socket
     |> assign(:page_title, "DAGs Listing")
     |> stream(:dags, dags)
     |> stream(:broken_dags, broken_dags)}
  end

  @impl true
  def handle_event("trigger_run", %{"id" => id}, socket) do
    dag_id = String.to_integer(id)
    {:ok, run} = Flows.create_run(%{dag_id: dag_id})

    run = Flows.get_run_with_tasks!(run.id) |> Trigger.dispatch_run()

    {:noreply, socket |> put_flash(:info, "Run #{run.id} triggered")}
  end

  @impl true
  def handle_info(
        {:dag, :file_updated,
         %{action: "removed", dag_name: name, parse_result: {:error, _error}}},
        socket
      ) do
    {:noreply, socket |> stream_delete(:dags, %{id: name})}
  end

  @impl true
  def handle_info(
        {:dag, :file_updated, %{action: "reload", dag_name: name, parse_result: {:error, error}}},
        socket
      ) do
    dag = Flows.get_dag_by_name(name)
    socket = stream_insert(socket, :broken_dags, %{id: name, dag: dag, error: error})
    socket = stream_delete(socket, :dags, %{id: name})
    {:noreply, socket}
  end

  @impl true
  def handle_info(
        {:dag, :file_updated, %{action: "reload", parse_result: {:ok, dag_def}}},
        socket
      ) do
    name = dag_def.name
    dag = Flows.get_dag_by_name(name)
    socket = insert_dag(socket, dag, dag_def)
    socket = stream_delete(socket, :broken_dags, %{id: dag.name})
    {:noreply, socket}
  end

  defp insert_dag(socket, dag, dag_def) do
    stream_insert(socket, :dags, %{id: dag.name, dag: dag, dag_def: dag_def})
  end
end
