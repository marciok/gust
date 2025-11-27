defmodule GustWeb.BreadcrumbsComponent do
  @moduledoc false
  use GustWeb, :live_component

  def render(assigns) do
    ~H"""
    <div class="breadcrumbs text-sm bg-white rounded shadow-sm overflow-hidden mb-4 px-4">
      <ul>
        <li>
          <.link id="dags-link" navigate={~p"/dags"}>
            DAGs
          </.link>
        </li>
        <li>
          <.link id="dag-runs-link" navigate={~p"/dags/#{@dag_def.name}/runs"}>
            {@dag_def.name}
          </.link>
        </li>
        <li :if={@run}>
          <.link id="dag-run-link" navigate={~p"/dags/#{@dag_def.name}/runs?run_id=#{@run.id}"}>
            {@run.id}
          </.link>
        </li>
        <li :if={@task}>
          <.link
            id="dag-run-task-link"
            navigate={~p"/dags/#{@dag_def.name}/runs?run_id=#{@run.id}&task_name=#{@task.name}"}
          >
            {@task.name}
          </.link>
        </li>
      </ul>
    </div>
    """
  end
end
