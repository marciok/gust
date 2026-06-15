defmodule GustWeb.DagLive.Dashboard do
  alias Gust.DAG.{Adapter, Loader, Terminator}
  alias Gust.DAG.Run.Trigger
  alias Gust.Flows
  alias Gust.Flows.Dag
  alias Gust.Flows.Run
  alias Gust.Flows.Task
  alias Gust.PubSub
  alias GustWeb.Mermaid
  use GustWeb, :live_view

  @page_size 30

  @impl true
  def mount(params, _session, socket) do
    page = parse_page(params["page"])
    dag = load_dag(page, params["name"])

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

  defp mount_success(socket, %Dag{runs: runs} = dag, dag_def, params, page) do
    selected_item = load_selected_item(params)
    expanded_items = get_expanded_items(selected_item)

    if connected?(socket), do: subscribe_updates(dag, runs)

    {:ok,
     socket
     |> assign(:dag_def, dag_def)
     |> assign(:page, page)
     |> assign(:error, {})
     |> assign(:dag, dag)
     |> assign(:selected_item, selected_item)
     |> assign(:item_name, get_name(selected_item))
     |> assign(:item_id, get_id(selected_item))
     |> assign_item_attrs(selected_item)
     |> assign(:reload_dag_file, {dag_def.file_path, time()})
     |> stream(:logs, get_logs(selected_item))
     |> assign(:expanded_item_ids, get_expanded_ids(expanded_items))
     |> stream(:expanded_items, expanded_items, dom_id: &"mapped-task-run-#{&1.id}")
     |> stream(:runs, runs |> Enum.reverse())}
  end

  defp get_expanded_items(nil), do: []
  defp get_expanded_items(%Task{}), do: []
  defp get_expanded_items(%Run{}), do: []
  defp get_expanded_items(tasks) when is_list(tasks), do: tasks

  defp get_expanded_ids(items), do: Enum.map(items, & &1.id)

  defp get_name(nil), do: nil

  defp get_name(%Task{name: name, map_index: nil}), do: name
  defp get_name(%Task{name: name, map_index: index}), do: "#{name} [#{index}]"
  defp get_name(%Run{id: id}), do: "Run #{id}"
  defp get_name([%Task{name: name} | _tail]), do: "#{name} []"

  defp get_id(nil), do: nil
  defp get_id(%Task{id: id}), do: id
  defp get_id(%Run{id: id}), do: id
  defp get_id([%Task{} | _tail]), do: nil

  defp get_status(nil), do: nil
  defp get_status(%Task{status: status}), do: status
  defp get_status(%Run{status: status}), do: status
  defp get_status([%Task{} | _tail]), do: nil

  defp get_timestamps(nil), do: {nil, nil}
  defp get_timestamps(%Task{inserted_at: ins, updated_at: up}), do: {ins, up}
  defp get_timestamps(%Run{inserted_at: ins, updated_at: up}), do: {ins, up}
  defp get_timestamps([%Task{} | _tail]), do: {nil, nil}

  defp get_params(nil), do: nil
  defp get_params(%Task{params: params}), do: params
  defp get_params(%Run{params: params}), do: params
  defp get_params([%Task{} | _tail]), do: %{}

  defp get_error(nil), do: nil
  defp get_error(%Task{error: error}), do: error
  defp get_error(%Run{}), do: %{}
  defp get_error([%Task{} | _tail]), do: %{}

  defp get_result(nil), do: nil
  defp get_result(%Task{result: result}), do: result
  defp get_result(%Run{}), do: %{}
  defp get_result([%Task{} | _tail]), do: %{}

  defp get_logs(item, level \\ nil)
  defp get_logs(nil, _level), do: []
  defp get_logs(%Task{} = task, level), do: Flows.get_logs(task.id, level)
  defp get_logs(%Run{}, _level), do: []
  defp get_logs([%Task{} | _tail], _level), do: []

  def get_expanded(%Task{name: name, run_id: run_id, map_index: index}) when index != nil do
    Flows.get_tasks_by_name(name, run_id)
  end

  def get_expanded(_item), do: []

  defp load_selected_item(params) do
    params
    |> fetch_selected_item()
    |> subscribe_selected_item()
  end

  defp fetch_selected_item(%{
         "run_id" => run_id,
         "task_name" => task_name,
         "task_index" => task_index
       }) do
    Flows.get_task_by_name(task_name, run_id, task_index)
  end

  defp fetch_selected_item(%{"run_id" => run_id, "task_name" => task_name}) do
    case Flows.get_tasks_by_name(task_name, run_id) do
      [] -> nil
      [task] -> task
      tasks -> tasks
    end
  end

  defp fetch_selected_item(%{"run_id" => run_id}) do
    Flows.get_run_with_tasks!(run_id)
  end

  defp fetch_selected_item(_params), do: nil

  defp subscribe_selected_item(nil), do: nil

  defp subscribe_selected_item(%Task{id: task_id} = task) do
    PubSub.subscribe_task(task_id)
    PubSub.subscribe_run(task.run_id)
    task
  end

  defp subscribe_selected_item(%Run{id: run_id} = run) do
    PubSub.subscribe_run(run_id)
    run
  end

  defp subscribe_selected_item([%Task{run_id: run_id} | _tail] = tasks) do
    PubSub.subscribe_run(run_id)
    tasks
  end

  defp parse_page(nil), do: 1

  defp parse_page(page) do
    case Integer.parse(page) do
      {page, ""} when page > 0 -> page
      _invalid -> 1
    end
  end

  defp mount_error(socket, dag) do
    {:ok,
     socket
     |> put_flash(:warning, "Syntax error! on #{dag.name}")
     |> push_navigate(to: ~g"/dags")}
  end

  defp handle_page(page, :next), do: page + 1
  defp handle_page(1, :prev), do: 1
  defp handle_page(page, :prev), do: page - 1

  defp subscribe_updates(dag, runs) do
    Enum.each(runs, fn run -> PubSub.subscribe_run(run.id) end)
    PubSub.subscribe_runs_for_dag(dag.id)
    PubSub.subscribe_file(dag.name)
  end

  def time, do: DateTime.utc_now() |> strftime()

  defp mermaid_chart(tasks), do: Mermaid.chart(tasks)

  defp read_code({file_path, _reload_time}), do: File.read!(file_path)
  defp reload_time({_file_path, reload_time}), do: reload_time

  @impl true
  def handle_event("cancel_task", %{"id" => task_id}, socket) do
    task = Flows.get_task!(task_id)

    {flash_level, flash} =
      case task.status do
        :running ->
          dag_def = socket.assigns.dag_def
          runtime = Adapter.impl!(dag_def.adapter, :runtime)
          Terminator.kill_task(task, :cancelled, runtime)
          {:info, "Task: #{task.name} was cancelled"}

        :retrying ->
          Terminator.cancel_timer(task, :cancelled)
          {:info, "Task: #{task.name} retrying cancelled"}

        _status ->
          {:info, "Task: #{task.name} is not running"}
      end

    {:noreply, put_flash(socket, flash_level, flash)}
  end

  @impl true
  def handle_event("filter_logs", %{"level" => level}, socket) do
    logs = get_logs(socket.assigns.selected_item, level)
    {:noreply, socket |> stream(:logs, logs, reset: true)}
  end

  @impl true
  def handle_event("restart", _params, socket) do
    flash_msg =
      case socket.assigns.selected_item do
        %Task{map_index: map_index} = task ->
          Trigger.reset_task(socket.assigns.dag_def.tasks, task, map_index)

          if map_index do
            "Task: #{task.name} [#{map_index}] was restarted"
          else
            "Task: #{task.name} was restarted"
          end

        [%Task{} = task | _tail] ->
          Trigger.reset_task(socket.assigns.dag_def.tasks, task, nil)
          "Task: #{task.name} was restarted"

        %Run{} = run ->
          run = Trigger.reset_run(run)
          "Run: #{run.id} was restarted"
      end

    {:noreply, socket |> put_flash(:info, flash_msg)}
  end

  @impl true
  def handle_event("trigger_run", %{"id" => id}, socket) do
    dag_id = String.to_integer(id)
    {:ok, run} = Flows.create_run(%{dag_id: dag_id})

    run = Flows.get_run_with_tasks!(run.id) |> Trigger.dispatch_run()

    {:noreply, socket |> stream_insert(:runs, run) |> put_flash(:info, "Run #{run.id} triggered")}
  end

  @impl true
  def handle_info({:task, :log, %{task_id: task_id, log_id: log_id}}, socket) do
    socket =
      if socket.assigns.item_id == task_id do
        log = Flows.get_log!(log_id)
        stream_insert(socket, :logs, log)
      else
        socket
      end

    {:noreply, socket}
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
        {:dag, :run_status, %{run_id: run_id, status: _status, task_id: task_id}},
        socket
      ) do
    run = Flows.get_run_with_tasks!(run_id)

    socket =
      if task_id do
        assign_task_reload(socket, task_id)
      else
        assign_run_reload(socket, run)
      end

    {:noreply, socket |> stream_insert(:runs, run)}
  end

  defp assign_run_reload(socket, run) do
    if socket.assigns.item_id == run.id do
      socket |> assign_item_attrs(run)
    else
      socket
    end
  end

  defp assign_task_reload(socket, task_id) do
    cond do
      task_id in socket.assigns.expanded_item_ids ->
        task = Flows.get_task!(task_id)
        stream_insert(socket, :expanded_items, task)

      socket.assigns.item_id == task_id ->
        task = Flows.get_task!(task_id)
        assign_item_attrs(socket, task)

      true ->
        socket
    end
  end

  defp pretty_json!(value) do
    Jason.encode_to_iodata!(value, pretty: true, escape_html: true)
  end

  defp selected_run_class(run_id, selected_item) do
    if run_id == selected_run_id(selected_item), do: "selected-run", else: ""
  end

  defp selected_run_id(nil), do: nil
  defp selected_run_id(%Run{id: id}), do: id
  defp selected_run_id(%Task{run_id: run_id}), do: run_id
  defp selected_run_id([%Task{run_id: run_id} | _tail]), do: run_id

  defp mapped_task?(dag_def, task_name) do
    dag_def.tasks[task_name][:map_over] != nil
  end

  defp selected_task(%Task{} = task), do: task
  defp selected_task([%Task{} = task | _tail]), do: task
  defp selected_task(_item), do: nil

  defp show_cancel?(%Task{}), do: true
  defp show_cancel?(_item), do: false

  defp restartable?([%Task{} | _tail], _status), do: true
  defp restartable?(_item, status), do: status in [:failed, :succeeded]

  defp assign_item_attrs(socket, selected_item) do
    {inserted_at, updated_at} = get_timestamps(selected_item)

    socket
    |> assign(:item_status, get_status(selected_item))
    |> assign(:item_inserted_at, inserted_at)
    |> assign(:item_updated_at, updated_at)
    |> assign(:item_params, get_params(selected_item))
    |> assign(:item_error, get_error(selected_item))
    |> assign(:item_result, get_result(selected_item))
  end
end
