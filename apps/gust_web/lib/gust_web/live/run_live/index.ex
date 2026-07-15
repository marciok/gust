defmodule GustWeb.RunLive.Index do
  alias Gust.DAG.Run.Trigger
  alias Gust.Flows
  alias Gust.PubSub
  use GustWeb, :live_view

  @completed_run_statuses [:failed, :succeeded]

  defguardp selected_runs_empty?(socket) when socket.assigns.selected_run_ids == []

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:page_title, "Listing Runs")}
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
    selected_status_param = status_param(selected_status)
    dag = get_dag_with_runs!(page, page_size, name, selected_status)

    {runs_count, pages} = count_and_pages(dag.id, selected_status, page_size)

    subscribe_dag_runs(socket, dag)

    {:noreply,
     socket
     |> assign(:dag_name, dag.name)
     |> assign(:dag_id, dag.id)
     |> assign(:page_size, page_size)
     |> assign(:runs_count, runs_count)
     |> assign(:page, page)
     |> assign(:selected_status, selected_status_param)
     |> assign(:selected_run_ids, [])
     |> assign(:run_status_options, run_status_options())
     |> assign(:all_selected?, false)
     |> assign(:pages, 1..pages)
     |> stream(:runs, dag.runs, reset: true)}
  end

  defp count_and_pages(dag_id, status, size) do
    count = Flows.count_runs_on_dag(dag_id, status)
    pages = max(div(count + size - 1, size), 1)
    {count, pages}
  end

  @impl true
  def handle_event("select_page", %{"page" => num}, socket) do
    dag_name = socket.assigns.dag_name
    page_size = socket.assigns.page_size
    selected_status = socket.assigns.selected_status

    {:noreply,
     socket
     |> push_patch(to: runs_path(dag_name, page_size, num, selected_status))}
  end

  @impl true
  def handle_event("filter_status", %{"status" => status}, socket) do
    dag_name = socket.assigns.dag_name
    page_size = socket.assigns.page_size

    {:noreply,
     socket
     |> push_patch(to: runs_path(dag_name, page_size, 1, status))}
  end

  @impl true
  def handle_event("select_runs", params, socket) do
    {:noreply,
     socket
     |> assign(:selected_run_ids, selected_run_ids(params))
     |> assign(:all_selected?, false)}
  end

  @impl true
  def handle_event("select_all", _params, socket) do
    selected? = !socket.assigns.all_selected?

    dag =
      get_dag_with_runs!(
        socket.assigns.page,
        socket.assigns.page_size,
        socket.assigns.dag_name,
        run_status(socket.assigns.selected_status)
      )

    run_ids = if selected?, do: Enum.map(dag.runs, & &1.id), else: []

    {:noreply,
     socket
     |> assign(:selected_run_ids, run_ids)
     |> assign(:all_selected?, selected?)
     |> stream(:runs, dag.runs, reset: true)}
  end

  @impl true
  def handle_event("batch_delete", _params, socket) when selected_runs_empty?(socket) do
    {:noreply, socket}
  end

  def handle_event("batch_delete", _params, socket) do
    {eligible_runs, skipped_runs} = socket |> selected_runs_on_dag() |> partition_batch_runs()

    {:ok, deleted_runs} =
      Flows.delete_runs_on_dag(socket.assigns.dag_id, Enum.map(eligible_runs, & &1.id))

    {:noreply,
     socket
     |> refresh_run_list()
     |> put_flash(:info, batch_summary(:deleted, deleted_runs, skipped_runs))}
  end

  @impl true
  def handle_event("batch_restart", _params, socket) when selected_runs_empty?(socket) do
    {:noreply, socket}
  end

  def handle_event("batch_restart", _params, socket) do
    {eligible_runs, skipped_runs} = socket |> selected_runs_on_dag() |> partition_batch_runs()
    restarted_runs = Enum.map(eligible_runs, &Trigger.reset_run/1)

    {:noreply,
     socket
     |> refresh_run_list()
     |> put_flash(:info, batch_summary(:restarted, restarted_runs, skipped_runs))}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    run = Flows.get_run!(id)
    {:ok, _} = Flows.delete_run(run)

    {:noreply,
     socket
     |> refresh_run_list(clear_selection?: false)}
  end

  @impl true
  def handle_info(
        {:dag, :run_started, %{run_id: run_id}},
        socket
      ) do
    run = Flows.get_run!(run_id)
    PubSub.subscribe_run(run_id)

    if status_matches?(run, socket.assigns.selected_status) do
      {:noreply, socket |> stream_insert(:runs, run, at: 0)}
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
      {:noreply,
       socket
       |> assign(:selected_run_ids, List.delete(socket.assigns.selected_run_ids, run.id))
       |> refresh_runs_count()
       |> stream_delete(:runs, run)}
    end
  end

  defp get_dag_with_runs!(page, size, name, status) do
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

  defp run_status(status) do
    Enum.find(Ecto.Enum.values(Flows.Run, :status), &(to_string(&1) == status))
  end

  defp selected_run_ids(params) do
    params
    |> Map.get("run_ids", [])
    |> Enum.map(&String.to_integer/1)
  end

  defp selected_runs_on_dag(socket) do
    Flows.get_runs_on_dag(socket.assigns.dag_id, socket.assigns.selected_run_ids)
  end

  defp partition_batch_runs(runs) do
    Enum.split_with(runs, &(&1.status in @completed_run_statuses))
  end

  defp batch_summary(action, processed_runs, []) do
    processed_runs |> length() |> processed_summary(action)
  end

  defp batch_summary(action, processed_runs, skipped_runs) do
    processed = processed_runs |> length() |> processed_summary(action)
    skipped = skipped_runs |> length() |> run_count("skipped")

    reasons =
      skipped_runs
      |> Enum.map(& &1.status)
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.map_join(" ", &skip_reason(&1, action))

    "#{processed}; #{skipped}: #{reasons}"
  end

  defp processed_summary(count, action), do: run_count(count, to_string(action))

  defp run_count(1, action), do: "1 run #{action}"
  defp run_count(count, action), do: "#{count} runs #{action}"

  defp skip_reason(status, action) do
    status = status |> to_string() |> String.capitalize()
    "#{status} runs cannot be #{action}."
  end

  defp status_param(nil), do: ""
  defp status_param(status), do: to_string(status)

  defp status_matches?(_run, ""), do: true
  defp status_matches?(run, status), do: to_string(run.status) == status

  defp refresh_runs_count(socket) do
    {runs_count, pages} =
      count_and_pages(
        socket.assigns.dag_id,
        run_status(socket.assigns.selected_status),
        socket.assigns.page_size
      )

    socket
    |> assign(:runs_count, runs_count)
    |> assign(:pages, 1..pages)
  end

  defp refresh_stream_runs(socket) do
    dag =
      get_dag_with_runs!(
        socket.assigns.page,
        socket.assigns.page_size,
        socket.assigns.dag_name,
        run_status(socket.assigns.selected_status)
      )

    subscribe_dag_runs(socket, dag)

    socket
    |> stream(:runs, dag.runs, reset: true)
  end

  defp subscribe_dag_runs(socket, dag) do
    if connected?(socket) do
      PubSub.subscribe_runs_for_dag(dag.id)
      Enum.each(dag.runs, fn %{id: id} -> PubSub.subscribe_run(id) end)
    end
  end

  defp refresh_run_list(socket, opts \\ []) do
    socket
    |> maybe_clear_selection(Keyword.get(opts, :clear_selection?, true))
    |> refresh_stream_runs()
    |> refresh_runs_count()
  end

  defp maybe_clear_selection(socket, true) do
    socket
    |> assign(:selected_run_ids, [])
    |> assign(:all_selected?, false)
  end

  defp maybe_clear_selection(socket, false), do: socket

  defp runs_path(name, page_size, page, ""),
    do: ~g"/dags/#{name}/runs?page_size=#{page_size}&page=#{page}"

  defp runs_path(name, page_size, page, status),
    do: ~g"/dags/#{name}/runs?page_size=#{page_size}&page=#{page}&status=#{status}"
end
