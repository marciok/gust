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
          :skipped -> "badge-warning"
          :retrying -> "badge-warning"
          :waiting -> "badge-warning"
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
  attr :selected, :boolean, default: false
  attr :status, :atom

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

  attr :run_id, :integer, required: true
  attr :name, :string, required: true
  attr :navigate, :string, required: true
  attr :rest, :global
  attr :task_data, :map, default: nil

  def interactive_task_cell(assigns) do
    if assigns[:task_data] do
      ~H"""
      <.link navigate={@navigate} {@rest}>
        <.task_cell
          selected={@task_data[:selected]}
          status={@task_data[:status]}
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
