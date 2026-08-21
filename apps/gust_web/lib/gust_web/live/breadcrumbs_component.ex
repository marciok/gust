defmodule GustWeb.BreadcrumbsComponent do
  @moduledoc false
  use GustWeb, :live_component

  alias Gust.Flows.{Run, Task}

  @impl true
  def update(assigns, socket) do
    selected_item = Map.get(assigns, :selected_item)

    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:pinned_run_id, fn -> nil end)
     |> assign(:run_id, get_run_id(selected_item))
     |> assign(:task_index, get_task_index(selected_item))
     |> assign(:task_name, get_task_name(selected_item))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="breadcrumbs-nav"
      class={[
        "breadcrumbs",
        "flex items-center justify-between gap-4",
        "text-sm bg-white rounded shadow-sm overflow-hidden mb-4 px-4"
      ]}
    >
      <ul class="min-w-0">
        <li>
          <.link id="dags-link" navigate={~g"/dags"}>
            DAGs
          </.link>
        </li>
        <li>
          <.link id="dag-runs-link" navigate={~g"/dags/#{@dag_def.name}/dashboard"}>
            {@dag_def.name}
          </.link>
        </li>
        <li :if={@run_id}>
          <.link
            id="dag-run-link"
            navigate={dashboard_path(@dag_def.name, [{"run_id", @run_id}], @pinned_run_id)}
          >
            {@run_id}
          </.link>
        </li>
        <li :if={@task_name}>
          <.link
            id="dag-run-task-link"
            navigate={
              dashboard_path(
                @dag_def.name,
                [{"run_id", @run_id}, {"task_name", @task_name}],
                @pinned_run_id
              )
            }
          >
            {@task_name}
          </.link>
        </li>
        <li :if={@task_index}>
          <.link
            id="dag-run-task-index-link"
            navigate={
              dashboard_path(
                @dag_def.name,
                [
                  {"run_id", @run_id},
                  {"task_name", @task_name},
                  {"task_index", @task_index}
                ],
                @pinned_run_id
              )
            }
          >
            [{@task_index}]
          </.link>
        </li>
      </ul>
      <.link
        :if={@pinned_run_id}
        id="clear-history-pinned"
        navigate={~g"/dags/#{@dag_def.name}/dashboard?page=1"}
        class={["badge", "badge-warning", "ml-auto shrink-0 gap-1"]}
        aria-label="Unpin history and return to latest runs"
        title="Unpin history and return to latest runs"
      >
        Pinned run {@pinned_run_id} <.icon name="hero-x-mark" class="h-3 w-3" />
      </.link>
    </div>
    """
  end

  defp get_run_id(%Task{run_id: run_id}), do: run_id
  defp get_run_id([%Task{run_id: run_id} | _tail]), do: run_id
  defp get_run_id(%Run{id: run_id}), do: run_id
  defp get_run_id(_selected_item), do: nil

  defp get_task_index(%Gust.Flows.Task{map_index: map_index}), do: map_index
  defp get_task_index(_selected_item), do: nil

  defp get_task_name(%Task{name: task_name}), do: task_name
  defp get_task_name([%Task{name: task_name} | _tail]), do: task_name
  defp get_task_name(_selected_item), do: nil

  defp dashboard_path(dag_name, params, pinned_run_id) do
    params = if pinned_run_id, do: params ++ [{"pinned_run_id", pinned_run_id}], else: params
    query = URI.encode_query(params)
    ~g"/dags/#{dag_name}/dashboard?#{query}"
  end
end
