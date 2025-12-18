defmodule GustWeb.RunLive.Index do
  alias Gust.Flows
  alias Gust.PubSub
  use GustWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Listing Runs")}
  end

  @impl true
  def handle_params(%{"name" => name, "page_size" => page_size, "page" => page}, _uri, socket) do
    page_size = String.to_integer(page_size)
    page = String.to_integer(page)

    dag = load_dag(page, page_size, name)
    runs_count = Flows.count_runs_on_dag(dag.id)
    pages = div(runs_count + page_size - 1, page_size)

    if connected?(socket) do
      PubSub.subscribe_runs_for_dag(dag.id)
      Enum.each(dag.runs, fn %{id: id} -> PubSub.subscribe_run(id) end)
    end

    {:noreply,
     socket
     |> assign(:dag, dag)
     |> assign(:page_size, page_size)
     |> assign(:runs_count, runs_count)
     |> assign(:page, page)
     |> assign(:pages, 1..pages)
     |> stream(:runs, dag.runs, reset: true)}
  end

  @impl true
  def handle_event("select_page", %{"page" => num}, socket) do
    dag = socket.assigns.dag
    page_size = socket.assigns.page_size

    {:noreply,
     socket |> push_patch(to: ~p"/dags/#{dag.name}/runs?page_size=#{page_size}&page=#{num}")}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    run = Flows.get_run!(id)
    {:ok, _} = Flows.delete_run(run)

    {:noreply, socket |> stream_delete(:runs, run)}
  end

  @impl true
  def handle_info(
        {:dag, :run_started, %{run_id: run_id}},
        socket
      ) do
    run = Flows.get_run!(run_id)
    PubSub.subscribe_run(run_id)

    {:noreply, stream_insert(socket, :runs, run, at: 0)}
  end

  @impl true
  def handle_info(
        {:dag, :run_status, %{run_id: run_id, status: _status}},
        socket
      ) do
    run = Flows.get_run!(run_id)

    {:noreply, stream_insert(socket, :runs, run)}
  end

  defp load_dag(page, size, name) do
    offset = (page - 1) * size

    Flows.get_dag_by_name_with_runs!(name, limit: size, offset: offset)
  end
end
