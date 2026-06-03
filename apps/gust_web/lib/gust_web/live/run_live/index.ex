defmodule GustWeb.RunLive.Index do
  alias Gust.Flows
  alias Gust.PubSub
  use GustWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Listing Runs")}
  end

  @impl true
  def handle_params(
        %{"name" => name, "page_size" => page_size, "page" => page} = params,
        _uri,
        socket
      ) do
    page_size = String.to_integer(page_size)
    page = String.to_integer(page)
    selected_status = run_status(params["status"])

    dag = load_dag(page, page_size, name, selected_status)
    runs_count = Flows.count_runs_on_dag(dag.id, selected_status)
    pages = max(div(runs_count + page_size - 1, page_size), 1)

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
     |> assign(:selected_status, status_param(selected_status))
     |> assign(:run_status_options, run_status_options())
     |> assign(:pages, 1..pages)
     |> stream(:runs, dag.runs, reset: true)}
  end

  @impl true
  def handle_event("select_page", %{"page" => num}, socket) do
    dag = socket.assigns.dag
    page_size = socket.assigns.page_size
    selected_status = socket.assigns.selected_status

    {:noreply,
     socket
     |> push_patch(to: runs_path(dag.name, page_size, num, selected_status))}
  end

  @impl true
  def handle_event("filter_status", %{"status" => status}, socket) do
    dag = socket.assigns.dag
    page_size = socket.assigns.page_size

    {:noreply,
     socket
     |> push_patch(to: runs_path(dag.name, page_size, 1, status))}
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

    if status_matches?(run, socket.assigns.selected_status) do
      {:noreply, stream_insert(socket, :runs, run, at: 0)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(
        {:dag, :run_status, %{run_id: run_id, status: _status}},
        socket
      ) do
    run = Flows.get_run!(run_id)

    if status_matches?(run, socket.assigns.selected_status) do
      {:noreply, stream_insert(socket, :runs, run)}
    else
      {:noreply, stream_delete(socket, :runs, run)}
    end
  end

  defp load_dag(page, size, name, status) do
    offset = (page - 1) * size

    Flows.get_dag_by_name_with_runs!(name, limit: size, offset: offset, status: status)
  end

  defp pretty_json!(value) do
    Jason.encode_to_iodata!(value, pretty: true, escape_html: true)
  end

  defp run_status_options do
    options =
      Enum.map(Ecto.Enum.values(Flows.Run, :status), fn status ->
        {status |> to_string() |> String.replace("_", " "), to_string(status)}
      end)

    [{"All statuses", ""} | options]
  end

  defp run_status(nil), do: nil
  defp run_status(""), do: nil

  defp run_status(status) do
    Enum.find(Ecto.Enum.values(Flows.Run, :status), &(to_string(&1) == status))
  end

  defp status_param(nil), do: ""
  defp status_param(status), do: to_string(status)

  defp status_matches?(_run, ""), do: true
  defp status_matches?(run, status), do: to_string(run.status) == status

  defp runs_path(name, page_size, page, ""),
    do: ~g"/dags/#{name}/runs?page_size=#{page_size}&page=#{page}"

  defp runs_path(name, page_size, page, status),
    do: ~g"/dags/#{name}/runs?page_size=#{page_size}&page=#{page}&status=#{status}"
end
