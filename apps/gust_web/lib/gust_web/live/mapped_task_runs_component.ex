defmodule GustWeb.MappedTaskRunsComponent do
  @moduledoc false
  use GustWeb, :live_component

  alias Gust.Flows.Task

  @impl true
  def update(assigns, socket) do
    status = Map.get(socket.assigns, :status, "")

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:status, status)
     |> assign_new(:status_options, fn -> status_filter_options(Task) end)
     |> stream_tasks(assigns.tasks, status)}
  end

  @impl true
  def handle_event("filter_status", %{"status" => status}, socket) do
    {:noreply,
     socket
     |> assign(:status, status)
     |> stream_tasks(socket.assigns.tasks, status)}
  end

  defp stream_tasks(socket, tasks, status) do
    stream(socket, :tasks, filter_tasks(tasks, status),
      dom_id: &"mapped-task-run-#{&1.id}",
      reset: true
    )
  end

  defp filter_tasks(tasks, status), do: Enum.filter(tasks, &status_matches?(&1, status))

  defp status_matches?(_task, ""), do: true
  defp status_matches?(task, status), do: to_string(task.status) == status

  defp task_show_path(task, dag_name, page, pinned_run_id) do
    query_params =
      [{"run_id", task.run_id}, {"task_name", task.name}, {"task_index", task.map_index}] ++
        history_position_params(page, pinned_run_id)

    query = URI.encode_query(query_params)
    ~g"/dags/#{dag_name}/dashboard?#{query}"
  end

  defp history_position_params(page, nil), do: [{"page", page}]
  defp history_position_params(_page, pinned_run_id), do: [{"pinned_run_id", pinned_run_id}]

  @impl true
  def render(assigns) do
    ~H"""
    <section class="dag-card__body">
      <div class="border-t border-base-content/20 -mx-4 mb-3" />
      <div class="flex flex-wrap items-center justify-between gap-3">
        <h4 class="text-sm font-semibold text-base-content/75">Task runs</h4>
        <.form
          for={%{}}
          id="mapped-task-status-filter"
          phx-change="filter_status"
          phx-target={@myself}
          class="mapped-task-status__filter-form"
        >
          <.input
            id="mapped-task-status-filter-select"
            value={@status}
            name="status"
            type="select"
            options={@status_options}
            class="select select-bordered select-sm h-8 w-36"
          />
        </.form>
      </div>

      <div class="overflow-x-auto overflow-y-auto max-h-96 mt-2">
        <table id="mapped-task-runs" class="min-w-full divide-y divide-base-content/15">
          <thead class="bg-base-200">
            <tr>
              <th class="px-3 py-2 text-left text-xs font-medium text-base-content/70 uppercase tracking-wider">
                Index
              </th>
              <th class="px-3 py-2 text-left text-xs font-medium text-base-content/70 uppercase tracking-wider">
                Status
              </th>
              <th class="px-3 py-2 text-left text-xs font-medium text-base-content/70 uppercase tracking-wider">
                Task ID
              </th>
              <th class="px-3 py-2 text-left text-xs font-medium text-base-content/70 uppercase tracking-wider">
                Updated
              </th>
              <th class="px-3 py-2 text-left text-xs font-medium text-base-content/70 uppercase tracking-wider">
                Action
              </th>
            </tr>
          </thead>
          <tbody
            id="mapped-task-run-list"
            class="bg-base-100 divide-y divide-base-content/15"
            phx-update="stream"
          >
            <tr :for={{id, task} <- @streams.tasks} id={id}>
              <td class="px-3 py-2 whitespace-nowrap">
                <span class="badge badge-xs">{task.map_index}</span>
              </td>
              <td class="px-3 py-2 whitespace-nowrap">
                <.status_badge status={task.status} />
              </td>
              <td class="px-3 py-2 whitespace-nowrap text-xs text-base-content font-mono">
                {task.id}
              </td>
              <td class="px-3 py-2 whitespace-nowrap text-xs text-base-content">
                {strftime(task.updated_at)}
              </td>
              <td class="px-3 py-2 whitespace-nowrap">
                <.link
                  class="btn btn-xs btn-soft"
                  navigate={task_show_path(task, @dag_name, @page, @pinned_run_id)}
                  id={"show-mapped-task-#{task.id}"}
                >
                  Show
                </.link>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>
    """
  end
end
