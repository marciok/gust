defmodule GustWeb.DagLive.Dashboard do
  alias Gust.DAG.{Loader, TaskStatus, Terminator}
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
  @aggregate_status_precedence [
    :failed,
    :upstream_failed,
    :retrying,
    :running,
    :waiting,
    :enqueued,
    :created,
    :skipped,
    :succeeded
  ]

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
        status: get_status(task_instances),
        selected: task_group_selected?(selected_item, task_instances)
      }
    end
  end

  defp task_group_selected?(nil, _tasks), do: false

  defp task_group_selected?([%Task{run_id: run_id, name: name} | _tail], tasks) do
    same_task_group?(tasks, run_id, name)
  end

  defp task_group_selected?(%Task{run_id: run_id, name: name}, tasks) do
    same_task_group?(tasks, run_id, name)
  end

  defp task_group_selected?(_selected_item, _tasks), do: false

  defp same_task_group?(tasks, run_id, name) do
    Enum.any?(tasks, &(&1.run_id == run_id and &1.name == name))
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
    selected_item = load_selected_item(params)
    mermaid_task_statuses = run_task_statuses(runs, selected_item)
    expanded_items = get_expanded_items(selected_item)
    logs = get_logs(selected_item)

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
     |> assign(:item_name, get_name(selected_item))
     |> assign(:item_id, get_id(selected_item))
     |> assign_item_attrs(selected_item)
     |> assign(:reload_dag_file, {dag_def.file_path, time()})
     |> stream(:logs, logs)
     |> assign(:empty_logs, logs == [])
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

  defp get_status([%Task{} | _tail] = tasks) do
    tasks
    |> Enum.map(& &1.status)
    |> aggregate_status()
  end

  defp aggregate_status(statuses) do
    statuses = MapSet.new(statuses)

    Enum.find(@aggregate_status_precedence, &MapSet.member?(statuses, &1))
  end

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
      [task] when is_nil(task.map_index) -> task
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

  defp mermaid_chart(tasks, nil, _selected_item), do: Mermaid.chart(tasks)

  defp mermaid_chart(tasks, selected_run_statuses, selected_item) do
    task_statuses =
      Map.new(tasks, fn {name, _task} ->
        {name, Map.get(selected_run_statuses, name, :none)}
      end)

    Mermaid.chart(tasks, task_statuses, selected_task_names(selected_item))
  end

  defp selected_task_names(%Task{name: name}), do: [name]
  defp selected_task_names([%Task{name: name} | _tail]), do: [name]
  defp selected_task_names(_selected_item), do: []

  defp run_task_statuses(_runs, nil), do: nil

  defp run_task_statuses(_runs, %Run{tasks: tasks}) do
    task_statuses(tasks)
  end

  defp run_task_statuses(runs, selected_item) do
    case Enum.find(runs, &(&1.id == selected_run_id(selected_item))) do
      %Run{tasks: tasks} -> task_statuses(tasks)
      nil -> selected_task_statuses(selected_item)
    end
  end

  defp selected_task_statuses(%Task{name: name, status: status}), do: %{name => status}
  defp selected_task_statuses(tasks) when is_list(tasks), do: task_statuses(tasks)

  defp task_statuses(tasks) do
    tasks
    |> Enum.group_by(& &1.name)
    |> Map.new(fn {name, task_instances} -> {name, get_status(task_instances)} end)
  end

  defp read_code({file_path, _reload_time}), do: File.read!(file_path)
  defp reload_time({_file_path, reload_time}), do: reload_time

  @impl true
  def handle_event("cancel", _params, socket) do
    {flash_kind, flash_msg} =
      case socket.assigns.selected_item do
        %Task{} = task ->
          handle_task_cancel(reload_task(task))

        [%Task{name: name} | _tail] = tasks ->
          results =
            tasks
            |> Enum.map(&reload_task/1)
            |> Enum.map(&handle_task_cancel/1)

          Enum.find(results, {:info, "All #{name} tasks are being cancelled"}, fn
            {:error, _message} -> true
            {:info, _message} -> false
          end)
      end

    {:noreply, socket |> put_flash(flash_kind, flash_msg)}
  end

  @impl true
  def handle_event("restart", _params, socket) do
    {flash_kind, flash_msg} =
      case socket.assigns.selected_item do
        %Task{map_index: map_index} = task ->
          result = Trigger.reset_task(socket.assigns.dag_def.tasks, task)
          restart_flash(result, task, map_index)

        [%Task{} = task | _tail] = tasks ->
          result = Trigger.reset_task(socket.assigns.dag_def.tasks, tasks)
          restart_flash(result, task, nil)

        %Run{} = run ->
          run = Trigger.reset_run(run)
          {:info, "Run: #{run.id} was restarted"}
      end

    {:noreply, socket |> put_flash(flash_kind, flash_msg)}
  end

  @impl true
  def handle_event("filter_logs", %{"level" => level}, socket) do
    logs = get_logs(socket.assigns.selected_item, level)

    {:noreply, socket |> stream(:logs, logs, reset: true) |> assign(:empty_logs, logs == [])}
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
      if selected_run_id(socket.assigns.selected_item) == run.id do
        assign(socket, :mermaid_task_statuses, task_statuses(run.tasks))
      else
        socket
      end

    {:noreply, socket |> stream_insert(:runs, run)}
  end

  defp handle_task_cancel(%Task{name: name, status: status} = task) do
    if TaskStatus.cancellable?(status) do
      case Terminator.cancel(task) do
        {:ok, _task} -> {:info, "Task: #{name} was cancelled"}
        {:error, reason} -> {:error, "Task: #{name} could not be cancelled: #{reason}"}
      end
    else
      {:info, "Task: #{name} is not running"}
    end
  end

  defp reload_task(%Task{id: id}), do: Flows.get_task!(id)

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
        statuses = Flows.get_task_statuses_by_name(task.name, task.run_id)

        socket
        |> assign(:item_status, aggregate_status(statuses))
        |> stream_insert(:expanded_items, task)

      socket.assigns.item_id == task_id ->
        task = Flows.get_task!(task_id)
        assign_item_attrs(socket, task)

      true ->
        socket
    end
  end

  defp selected_run_class(run_id, selected_item) do
    if run_id == selected_run_id(selected_item), do: "selected-run", else: ""
  end

  defp selected_run_id(nil), do: nil
  defp selected_run_id(%Run{id: id}), do: id
  defp selected_run_id(%Task{run_id: run_id}), do: run_id
  defp selected_run_id([%Task{run_id: run_id} | _tail]), do: run_id

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

  defp cancelable?(%Task{}, status), do: cancellable_status?(status)

  defp cancelable?([%Task{} | _tasks] = tasks, _status) do
    Enum.any?(tasks, &cancellable_status?(&1.status))
  end

  defp cancelable?(_item, _status), do: false
  defp cancellable_status?(status), do: TaskStatus.cancellable?(status)

  defp restartable?(_item, status), do: TaskStatus.restartable?(status)

  defp restart_flash({:error, reason}, task, _map_index) do
    {:error, "Task: #{task.name} could not be restarted: #{reason}"}
  end

  defp restart_flash(_result, task, nil), do: {:info, "Task: #{task.name} was restarted"}

  defp restart_flash(_result, task, map_index),
    do: {:info, "Task: #{task.name} [#{map_index}] was restarted"}

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
