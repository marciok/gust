defmodule GustWeb.DagLive.Dashboard do
  alias Gust.DAG.{Loader, Terminator}
  alias Gust.DAG.Run.Trigger
  alias Gust.Flows
  alias Gust.Flows.Run
  alias Gust.PubSub
  alias GustWeb.Mermaid
  use GustWeb, :live_view

  @page_size 30

  @impl true
  def mount(params, _session, socket) do
    page = params["page"] || "1"
    dag = load_dag(String.to_integer(page), params["name"])

    dag_def = Loader.get_definition(dag.id)

    case dag_def do
      {:ok, dag_def} ->
        mount_success(socket, dag, dag_def, params, page)

      {:error, _error} ->
        mount_error(socket, dag)
    end
  end

  defp load_dag(page, name) do
    offset = (page - 1) * @page_size

    Flows.get_dag_with_runs_and_tasks!(name, limit: @page_size, offset: offset)
  end

  defp mount_success(socket, %Flows.Dag{runs: runs} = dag, dag_def, params, page) do
    selected_run =
      if params["run_id"], do: Flows.get_run!(params["run_id"])

    {selected_task, logs} =
      maybe_get_task(params["task_name"], params["run_id"]) || {nil, []}

    if connected?(socket), do: subscribe_updates(dag, runs)

    {:ok,
     socket
     |> assign(:dag_def, dag_def)
     |> assign(:page, page)
     |> assign(:error, {})
     |> assign(:dag, dag)
     |> assign(:selected_task, selected_task)
     |> assign(:selected_run, selected_run)
     |> assign(:reload_dag_file, {dag_def.file_path, time()})
     |> stream(:logs, logs)
     |> stream(:runs, runs |> Enum.reverse())}
  end

  defp mount_error(socket, dag) do
    {:ok,
     socket
     |> put_flash(:warning, "Syntax error! on #{dag.name}")
     |> push_navigate(to: ~p"/dags")}
  end

  defp handle_page(page, :next), do: String.to_integer(page) + 1
  defp handle_page("1", :prev), do: 1
  defp handle_page(page, :prev), do: String.to_integer(page) - 1

  defp maybe_get_task(nil, nil), do: nil
  defp maybe_get_task(nil, _run_id), do: nil

  defp maybe_get_task(task_name, run_id) do
    task = Flows.get_task_by_name_run_with_logs(task_name, run_id)
    PubSub.subscribe_task(task.id)
    {task, task.logs}
  end

  defp subscribe_updates(dag, runs) do
    Enum.each(runs, fn run -> PubSub.subscribe_run(run.id) end)
    PubSub.subscribe_runs_for_dag(dag.id)
    PubSub.subscribe_file(dag.name)
  end

  def time, do: DateTime.utc_now() |> DateTime.to_iso8601()

  defp mermaid_chart(tasks), do: Mermaid.chart(tasks)

  defp read_code({file_path, _reload_time}), do: File.read!(file_path)
  defp reload_time({_file_path, reload_time}), do: reload_time

  @impl true
  def handle_event("cancel_task", %{"id" => task_id}, socket) do
    task = Flows.get_task!(task_id)
    # TODO: Redo so it called by pubsub

    flash =
      case task.status do
        :running ->
          Terminator.kill_task(task, :cancelled)
          "Task: #{task.name} was cancelled"

        :retrying ->
          Terminator.cancel_timer(task, :cancelled)
          "Task: #{task.name} retrying cancelled"
      end

    {:noreply, socket |> put_flash(:info, flash)}
  end

  @impl true
  def handle_event("filter_logs", %{"level" => level}, socket) do
    task = socket.assigns.selected_task |> get_task_with_logs(level)
    {:noreply, socket |> stream(:logs, task.logs, reset: true)}
  end

  @impl true
  def handle_event("restart_run", %{"id" => run_id}, socket) do
    run = Flows.get_run!(run_id) |> Trigger.reset_run()

    {:noreply, socket |> put_flash(:info, "Run: #{run.id} was restarted")}
  end

  @impl true
  def handle_event("restart_task", %{"id" => task_id}, socket) do
    dag_def = socket.assigns.dag_def
    task = Flows.get_task!(task_id)
    tasks_graph = dag_def.tasks

    Trigger.reset_task(tasks_graph, task)

    {:noreply, socket |> put_flash(:info, "Task: #{task.name} was restarted")}
  end

  @impl true
  def handle_event("trigger_run", %{"id" => id}, socket) do
    dag_id = String.to_integer(id)
    {:ok, run} = Flows.create_run(%{dag_id: dag_id})

    run = Flows.get_run_with_tasks!(run.id) |> Trigger.dispatch_run()

    {:noreply, socket |> stream_insert(:runs, run) |> put_flash(:info, "Run #{run.id} triggered")}
  end

  @impl true
  def handle_info({:task, :log, %{task_id: _task_id, log_id: log_id}}, socket) do
    log = Flows.get_log!(log_id)

    {:noreply, socket |> stream_insert(:logs, log)}
  end

  @impl true
  def handle_info(
        {:dag, :file_updated,
         %{action: "reload", dag_name: _name, parse_result: {:error, error}}},
        socket
      ) do
    dag_def = socket.assigns.dag_def

    {:noreply,
     socket
     |> assign(:error, error)
     |> assign(:reload_dag_file, {dag_def.file_path, time()})}
  end

  @impl true
  def handle_info(
        {:dag, :file_updated, %{action: "reload", dag_name: _name, parse_result: {:ok, dag_def}}},
        socket
      ) do
    {:noreply,
     socket
     |> assign(:dag_def, dag_def)
     |> assign(:error, {})
     |> assign(:reload_dag_file, {dag_def.file_path, time()})}
  end

  @impl true
  def handle_info(
        {:dag, :run_started, %{run_id: run_id}},
        socket
      ) do
    run = Flows.get_run_with_tasks!(run_id)
    PubSub.subscribe_run(run_id)

    {:noreply, stream_insert(socket, :runs, run)}
  end

  @impl true
  def handle_info(
        {:dag, :run_status, %{run_id: run_id, status: _status}},
        socket
      ) do
    run = Flows.get_run_with_tasks!(run_id)

    {:noreply, stream_insert(socket, :runs, run)}
  end

  defp pretty_json!(value) do
    Jason.encode_to_iodata!(value, pretty: true, escape_html: true)
  end

  defp selected_run_class(_run_id, nil), do: ""

  defp selected_run_class(run_id, selected_run) do
    if run_id == selected_run.id, do: "selected-run", else: ""
  end

  defp get_task_with_logs(task, ""),
    do: Flows.get_task_by_name_run_with_logs(task.name, task.run_id)

  defp get_task_with_logs(task, level),
    do: Flows.get_task_by_name_run_with_logs(task.name, task.run_id, level)
end
