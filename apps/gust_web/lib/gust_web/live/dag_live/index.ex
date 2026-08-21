defmodule GustWeb.DagLive.Index do
  alias Gust.DAG.Loader
  alias Gust.DAG.Run.Trigger
  alias Gust.Flows
  alias Gust.PubSub
  use GustWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    PubSub.subscribe_all_files("update")

    failed_runs_only? = false
    {dags, broken_dags} = list_dags(failed_runs_only?)

    {:ok,
     socket
     |> assign(:page_title, "DAGs Listing")
     |> assign(:failed_runs_only?, failed_runs_only?)
     |> assign_filter_form(failed_runs_only?)
     |> stream(:dags, dags)
     |> stream(:broken_dags, broken_dags)}
  end

  @impl true
  def handle_event("filter_dags", %{"filters" => filters}, socket) do
    failed_runs_only? = filters["failed_runs_only"] == "true"
    {dags, _broken_dags} = list_dags(failed_runs_only?)

    {:noreply,
     socket
     |> assign(:failed_runs_only?, failed_runs_only?)
     |> assign_filter_form(failed_runs_only?)
     |> stream(:dags, dags, reset: true)}
  end

  @impl true
  def handle_event("trigger_run", %{"id" => id}, socket) do
    dag_id = String.to_integer(id)
    {:ok, run} = Flows.create_run(%{dag_id: dag_id})

    run = Flows.get_run_with_tasks!(run.id) |> Trigger.dispatch_run()

    {:noreply, socket |> put_flash(:info, "Run #{run.id} triggered")}
  end

  defp list_dags(failed_runs_only?) do
    dag_defs = Loader.get_definitions()

    dags_by_id =
      dag_defs
      |> Map.keys()
      |> Flows.get_dags_with_recent_runs()
      |> Map.new(&{&1.id, &1})

    dags =
      for {dag_id, {:ok, dag_def}} <- dag_defs do
        dag = Map.fetch!(dags_by_id, dag_id)
        %{id: dag.name, dag: dag, dag_def: dag_def, recent_runs: dag.runs}
      end

    dags = Enum.filter(dags, &show_dag?(&1.dag, failed_runs_only?))

    broken_dags =
      for {dag_id, {:error, error}} <- dag_defs do
        dag = Map.fetch!(dags_by_id, dag_id)
        %{id: dag.name, dag: dag, error: error}
      end

    {dags, broken_dags}
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
    dag = Flows.get_dag_with_recent_runs(name)

    socket =
      if show_dag?(dag, socket.assigns.failed_runs_only?) do
        insert_dag(socket, dag, dag_def)
      else
        socket
      end

    socket = stream_delete(socket, :broken_dags, %{id: dag.name})
    {:noreply, socket}
  end

  defp assign_filter_form(socket, failed_runs_only?) do
    assign(
      socket,
      :filter_form,
      to_form(%{"failed_runs_only" => failed_runs_only?}, as: :filters)
    )
  end

  defp show_dag?(_dag, false), do: true
  defp show_dag?(dag, true), do: Enum.any?(dag.runs, &(&1.status == :failed))

  defp insert_dag(socket, dag, dag_def) do
    stream_insert(socket, :dags, %{
      id: dag.name,
      dag: dag,
      dag_def: dag_def,
      recent_runs: dag.runs
    })
  end
end
