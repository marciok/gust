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
     |> assign(:run_id, get_run_id(selected_item))
     |> assign(:task_index, get_task_index(selected_item))
     |> assign(:task_name, get_task_name(selected_item))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="breadcrumbs text-sm bg-white rounded shadow-sm overflow-hidden mb-4 px-4">
      <ul>
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
          <.link id="dag-run-link" navigate={~g"/dags/#{@dag_def.name}/dashboard?run_id=#{@run_id}"}>
            {@run_id}
          </.link>
        </li>
        <li :if={@task_name}>
          <.link
            id="dag-run-task-link"
            navigate={~g"/dags/#{@dag_def.name}/dashboard?run_id=#{@run_id}&task_name=#{@task_name}"}
          >
            {@task_name}
          </.link>
        </li>
        <li :if={@task_index}>
          <.link
            id="dag-run-task-index-link"
            navigate={
              ~g"/dags/#{@dag_def.name}/dashboard?run_id=#{@run_id}&task_name=#{@task_name}&task_index=#{@task_index}"
            }
          >
            [{@task_index}]
          </.link>
        </li>
      </ul>
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
end
