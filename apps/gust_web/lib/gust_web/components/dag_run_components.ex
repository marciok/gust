defmodule GustWeb.DagRunComponents do
  @moduledoc false

  use Phoenix.Component
  use Gettext, backend: GustWeb.Gettext

  attr :status, :atom, required: true
  attr :rest, :global, doc: "data-testid, etc."

  def status_badge(assigns) do
    ~H"""
    <div
      {@rest}
      class={[
        "badge",
        "badge-outline",
        case @status do
          :succeeded -> "badge-success"
          :failed -> "badge-error"
          :upstream_failed -> "badge-warning"
          _ -> "badge-info"
        end
      ]}
    >
      {@status}
    </div>
    """
  end

  attr :level, :string, required: true

  def log_badge(assigns) do
    ~H"""
    <div class={[
      "badge",
      "badge-soft",
      case @level do
        "debug" -> "badge-info"
        "info" -> "badge-info"
        "warn" -> "badge-warning"
        "error" -> "badge-error"
      end
    ]}>
      {@level}
    </div>
    """
  end

  attr :id, :string, required: true
  attr :selected, :string
  attr :status, :string

  def task_cell(assigns) do
    assigns =
      assign_new(assigns, :classes, fn ->
        base_classes =
          if assigns[:status], do: ["status-#{assigns[:status]}", "active"], else: ["status-none"]

        classes = base_classes ++ if assigns[:selected], do: ["selected"], else: []

        Enum.join(classes, " ")
      end)

    ~H"""
    <div
      id={"#{@id}"}
      class={"task-grid-cell  border rounded #{@classes}"}
    >
    </div>
    """
  end

  attr :run_id, :string, required: true
  attr :ran_tasks, :list, required: true
  attr :name, :string, required: true
  attr :selected_task, :map, required: true
  attr :navigate, :string, required: true
  attr :rest, :global

  def interactive_task_cell(assigns) do
    assigns =
      assign_new(assigns, :current_task_ran, fn ->
        assigns[:ran_tasks] |> Enum.find(&(&1.name == assigns[:name]))
      end)

    if assigns[:current_task_ran] do
      ~H"""
      <.link navigate={@navigate} {@rest}>
        <.task_cell
          selected={if @selected_task, do: @selected_task.id == @current_task_ran.id, else: false}
          status={@current_task_ran.status}
          id={"#{@name}-at-run-#{@run_id}"}
        />
      </.link>
      """
    else
      ~H"""
      <.task_cell id={"#{@name}-at-run-#{@run_id}"} />
      """
    end
  end
end
