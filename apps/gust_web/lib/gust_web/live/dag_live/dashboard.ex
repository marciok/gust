defmodule GustWeb.DagLive.Dashboard do
  alias __MODULE__.{MappedTasks, SelectedItem, TaskActions}
  alias Gust.DAG.{Loader, TaskStatus}
  alias Gust.DAG.Run.ErrorReporter.ExternalReference
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
    pinned_run_id = params["pinned_run_id"]
    page = if pinned_run_id, do: 1, else: parse_page(params["page"])
    dag = load_dag(page, params["name"], pinned_run_id)

    dag_def = Loader.get_definition(dag.id)

    case dag_def do
      {:ok, dag_def} ->
        mount_success(socket, dag, dag_def, params, page, pinned_run_id)

      {:error, _error} ->
        mount_error(socket, dag)
    end
  end

  defp task_cell_data(task_name, tasks_by_name, selected_item) do
    task_instances = Map.get(tasks_by_name, task_name, [])

    if task_instances != [] do
      %{
        status: SelectedItem.status(task_instances),
        selected: SelectedItem.task_group_selected?(selected_item, task_instances)
      }
    end
  end

  defp load_dag(page, name, nil) do
    offset = (page - 1) * @page_size

    Flows.get_dag_with_runs_and_tasks!(name, limit: @page_size, offset: offset)
  end

  defp load_dag(_page, name, pinned_run_id) do
    Flows.get_dag_with_runs_and_tasks!(name,
      limit: @page_size,
      pinned_run_id: pinned_run_id
    )
  end

  defp mount_success(socket, %Dag{runs: runs} = dag, dag_def, params, page, pinned_run_id) do
    selected_item = SelectedItem.load(params)
    mermaid_task_statuses = run_task_statuses(runs, selected_item)
    expanded_items = SelectedItem.expanded_items(selected_item)
    logs = SelectedItem.logs(selected_item)

    if connected?(socket), do: subscribe_updates(dag, runs)

    {:ok,
     socket
     |> assign(:dag_def, dag_def)
     |> assign(:page, page)
     |> assign(:pinned_run_id, pinned_run_id)
     |> assign(:error, {})
     |> assign(:dag, dag)
     |> assign(:selected_item, selected_item)
     |> assign(:mermaid_task_statuses, mermaid_task_statuses)
     |> assign(SelectedItem.attributes(selected_item))
     |> assign(:reload_dag_file, {dag_def.file_path, time()})
     |> assign_mapped_task_status("")
     |> assign(:task_selection_form, to_form(%{"task_ids" => []}))
     |> assign(:mapped_task_status_options, status_filter_options(Task))
     |> assign(:selected_task_ids, [])
     |> stream(:logs, logs)
     |> assign(:empty_logs, logs == [])
     |> assign(:expanded_item_ids, SelectedItem.expanded_ids(selected_item))
     |> stream(:mapped_tasks, expanded_items, dom_id: &mapped_task_dom_id/1)
     |> stream(:runs, runs |> Enum.reverse())}
  end

  def get_expanded(item), do: SelectedItem.expanded(item)

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

  defp mermaid_chart(tasks, nil, _selected_item), do: Mermaid.chart(tasks)

  defp mermaid_chart(tasks, selected_run_statuses, selected_item) do
    task_statuses =
      Map.new(tasks, fn {name, _task} ->
        {name, Map.get(selected_run_statuses, name, :none)}
      end)

    Mermaid.chart(tasks, task_statuses, SelectedItem.task_names(selected_item))
  end

  defp run_task_statuses(_runs, nil), do: nil

  defp run_task_statuses(_runs, %Run{tasks: tasks}) do
    task_statuses(tasks)
  end

  defp run_task_statuses(runs, selected_item) do
    case Enum.find(runs, &(&1.id == SelectedItem.run_id(selected_item))) do
      %Run{tasks: tasks} -> task_statuses(tasks)
      nil -> selected_task_statuses(selected_item)
    end
  end

  defp selected_task_statuses(%Task{name: name, status: status}), do: %{name => status}
  defp selected_task_statuses(tasks) when is_list(tasks), do: task_statuses(tasks)

  defp task_statuses(tasks) do
    tasks
    |> Enum.group_by(& &1.name)
    |> Map.new(fn {name, task_instances} -> {name, SelectedItem.status(task_instances)} end)
  end

  defp read_code({file_path, _reload_time}), do: File.read!(file_path)
  defp reload_time({_file_path, reload_time}), do: reload_time

  defp code_language(%{file_path: file_path}) do
    case Path.extname(file_path) do
      extension when extension in [".yml", ".yaml"] -> "yaml"
      ".py" -> "python"
      _extension -> "elixir"
    end
  end

  @impl true
  def handle_event("filter_mapped_task_status", %{"status" => status}, socket) do
    {:noreply,
     socket
     |> assign_mapped_task_status(status)
     |> clear_task_selection()
     |> stream_mapped_tasks(socket.assigns.selected_item, status)}
  end

  @impl true
  def handle_event("select_mapped_tasks", params, socket) do
    selected_ids = MappedTasks.selected_ids(socket.assigns.selected_item, params)

    {:noreply,
     socket
     |> assign(:selected_task_ids, selected_ids)
     |> assign_task_selection_form()
     |> stream_mapped_tasks(socket.assigns.selected_item, socket.assigns.mapped_task_status)}
  end

  @impl true
  def handle_event("cancel", _params, socket) do
    socket =
      case socket.assigns.selected_item do
        %Task{} = task ->
          {flash_kind, flash_msg} = TaskActions.cancel(TaskActions.reload(task))
          put_flash(socket, flash_kind, flash_msg)

        [%Task{} | _tasks] ->
          cancel_selected_tasks(socket, selected_mapped_tasks(socket))
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("restart", _params, socket) do
    socket =
      case socket.assigns.selected_item do
        %Task{} = task ->
          {flash_kind, flash_msg} = TaskActions.restart(socket.assigns.dag_def.tasks, task)
          put_flash(socket, flash_kind, flash_msg)

        %Run{} = run ->
          run = Trigger.reset_run(run)
          put_flash(socket, :info, "Run: #{run.id} was restarted")

        [%Task{} | _tasks] ->
          restart_selected_tasks(socket, selected_mapped_tasks(socket))
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("restart_all", _params, socket) do
    socket =
      case socket.assigns.selected_item do
        [%Task{} | _tasks] = tasks ->
          {flash_kind, flash_msg} = TaskActions.restart_group(socket.assigns.dag_def.tasks, tasks)

          put_flash(socket, flash_kind, flash_msg)
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_logs", %{"level" => level}, socket) do
    logs = SelectedItem.logs(socket.assigns.selected_item, level)

    {:noreply, socket |> stream(:logs, logs, reset: true) |> assign(:empty_logs, logs == [])}
  end

  @impl true
  def handle_event("show_mapped_task", %{"task-id" => task_id}, socket) do
    task = Flows.get_task!(task_id)

    path =
      dashboard_item_path(
        socket.assigns.dag_def.name,
        task.run_id,
        socket.assigns.page,
        socket.assigns.pinned_run_id,
        [{"task_name", task.name}, {"task_index", task.map_index}]
      )

    {:noreply, push_navigate(socket, to: path)}
  end

  @impl true
  def handle_event("trigger_run", %{"id" => id}, socket) do
    dag_id = String.to_integer(id)
    {:ok, run} = Flows.create_run(%{dag_id: dag_id})

    Trigger.dispatch_run(run)
    run = Flows.get_run_with_tasks!(run.id)

    socket =
      if socket.assigns.pinned_run_id do
        put_flash(
          socket,
          :warning,
          "Run #{run.id} triggered. Unpin your history to view it."
        )
      else
        socket
        |> stream_insert(:runs, run)
        |> put_flash(:info, "Run #{run.id} triggered")
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:task, :updated, %{task_id: task_id}}, socket) do
    {:noreply, assign_task_reload(socket, task_id)}
  end

  @impl true
  def handle_info({:task, :log, %{task_id: task_id, log_id: log_id}}, socket) do
    socket =
      if socket.assigns.item_id == task_id do
        log = Flows.get_log!(log_id)

        socket
        |> stream_insert(:logs, log)
        |> assign(:empty_logs, false)
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
        {:dag, :run_started, %{run_id: _run_id}},
        %{assigns: %{pinned_run_id: pinned_run_id}} = socket
      )
      when not is_nil(pinned_run_id) do
    {:noreply, socket}
  end

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

    socket =
      if SelectedItem.run_id(socket.assigns.selected_item) == run.id do
        assign(socket, :mermaid_task_statuses, task_statuses(run.tasks))
      else
        socket
      end

    {:noreply, socket |> stream_insert(:runs, run)}
  end

  defp assign_run_reload(socket, run) do
    if socket.assigns.item_id == run.id do
      socket
      |> assign(:selected_item, run)
      |> assign_item_attrs(run)
    else
      socket
    end
  end

  defp assign_task_reload(socket, task_id) do
    cond do
      task_id in socket.assigns.expanded_item_ids ->
        task = Flows.get_task!(task_id)
        tasks = Flows.get_tasks_by_name(task.name, task.run_id)

        socket
        |> assign(:selected_item, tasks)
        |> assign(:item_status, SelectedItem.status(tasks))
        |> stream_mapped_tasks(tasks, socket.assigns.mapped_task_status)

      socket.assigns.item_id == task_id ->
        task = Flows.get_task!(task_id)

        socket
        |> assign(:selected_item, task)
        |> assign_item_attrs(task)

      true ->
        socket
    end
  end

  defp selected_run_class(run_id, selected_item) do
    if run_id == SelectedItem.run_id(selected_item), do: "selected-run", else: ""
  end

  defp dashboard_item_path(name, run_id, page, pinned_run_id, extra_params \\ []) do
    query_params =
      [{"run_id", run_id}] ++
        extra_params ++ history_position_params(page, pinned_run_id)

    query = URI.encode_query(query_params)
    ~g"/dags/#{name}/dashboard?#{query}"
  end

  defp history_position_params(page, nil), do: [{"page", page}]
  defp history_position_params(_page, pinned_run_id), do: [{"pinned_run_id", pinned_run_id}]

  defp mapped_task?(dag_def, task_name) do
    dag_def.tasks[task_name][:map_over] != nil
  end

  defp format_stacktrace(stacktrace) do
    Enum.map_join(stacktrace, "\n", fn frame ->
      call = "#{frame["module"]}.#{frame["function"]}/#{frame["arity"]}"

      location =
        [frame["file"], frame["line"], frame["column"]]
        |> Enum.reject(&is_nil/1)
        |> Enum.join(":")

      if location == "", do: call, else: "#{location} #{call}"
    end)
  end

  defp selected_mapped_tasks(socket) do
    MappedTasks.select(socket.assigns.selected_item, socket.assigns.selected_task_ids)
  end

  defp assign_mapped_task_status(socket, status) do
    socket
    |> assign(:mapped_task_status, status)
    |> assign(:mapped_task_status_form, to_form(%{"status" => status}))
  end

  defp assign_task_selection_form(socket) do
    task_ids = Enum.map(socket.assigns.selected_task_ids, &to_string/1)
    assign(socket, :task_selection_form, to_form(%{"task_ids" => task_ids}))
  end

  defp clear_task_selection(socket) do
    socket
    |> assign(:selected_task_ids, [])
    |> assign_task_selection_form()
  end

  defp stream_mapped_tasks(socket, tasks, status) do
    stream(socket, :mapped_tasks, MappedTasks.filter(tasks, status),
      dom_id: &mapped_task_dom_id/1,
      reset: true
    )
  end

  defp mapped_task_dom_id(task), do: "mapped-task-run-#{task.id}"

  defp cancel_selected_tasks(socket, selected_tasks) do
    socket = reset_mapped_tasks(socket)
    flash = selected_tasks |> TaskActions.filter(:cancellable?) |> TaskActions.cancel_many()
    put_task_flash(socket, flash)
  end

  defp restart_selected_tasks(socket, selected_tasks) do
    socket = reset_mapped_tasks(socket)
    tasks = TaskActions.filter(selected_tasks, :restartable?)
    flash = TaskActions.restart_many(socket.assigns.dag_def.tasks, tasks)
    put_task_flash(socket, flash)
  end

  defp put_task_flash(socket, nil), do: socket
  defp put_task_flash(socket, {flash_kind, message}), do: put_flash(socket, flash_kind, message)

  defp reset_mapped_tasks(socket) do
    socket
    |> clear_task_selection()
    |> stream_mapped_tasks(socket.assigns.selected_item, socket.assigns.mapped_task_status)
  end

  defp cancelable?([%Task{} | _tasks] = tasks, _status, selected_ids),
    do: MappedTasks.cancelable?(tasks, selected_ids)

  defp cancelable?(%Task{}, status, _selected_ids), do: TaskStatus.cancellable?(status)
  defp cancelable?(_item, _status, _selected_ids), do: false

  defp restartable?([%Task{} | _tasks] = tasks, _status, selected_ids),
    do: MappedTasks.restartable?(tasks, selected_ids)

  defp restartable?(_item, status, _selected_ids), do: TaskStatus.restartable?(status)

  defp restartable_group?(tasks), do: MappedTasks.restartable?(tasks)

  defp action_label(action, [_task | _tasks], _item_name), do: "#{action} selected"
  defp action_label(action, _item, item_name), do: "#{action} `#{item_name}`"

  defp assign_item_attrs(socket, selected_item) do
    assign(socket, SelectedItem.attributes(selected_item))
  end
end
