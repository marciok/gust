defmodule GustWeb.DagSummaryComponent do
  @moduledoc false
  use GustWeb, :live_component
  alias Gust.DAG.Run.Trigger
  alias Gust.Flows

  @impl true
  def handle_event("toggle_enabled", %{"id" => dag_id}, socket) do
    {:ok, dag} = Flows.get_dag!(dag_id) |> Flows.toggle_enabled()

    if dag.enabled do
      Trigger.dispatch_all_runs(dag.id)
    end

    {:noreply, socket |> assign(:dag, dag)}
  end

  defp format_error(%CompileError{file: _file, description: description, line: _line}),
    do: description

  @impl true
  def render(assigns) do
    ~H"""
    <div class="dag-card mb-4">
      <div :if={map_size(@dag_def.error) > 0} class="dag-card__notice">
        <div class="alert alert-error shadow-sm dag-card__alert" role="alert">
          <span id={"dag-error-#{@id}"}>
            <strong>{format_error(@dag_def.error)}</strong>
          </span>
        </div>
      </div>

      <div :if={length(@dag_def.messages) > 0} class="dag-card__notice">
        <div class="bg-warning text-warning-content rounded-lg p-4 shadow-sm space-y-2 dag-card__alert">
          <h2 class="text-md font-semibold">Warnings</h2>
          <ul class="list-disc list-inside text-sm">
            <%= for message <- @dag_def.messages do %>
              <li>{message.message}</li>
            <% end %>
          </ul>
        </div>
      </div>

      <section class="dag-card__header">
        <div class="dag-card__toggle-row">
          <span class={[
            "dag-card__state",
            @dag.enabled && "bg-success text-success-content",
            !@dag.enabled && "bg-slate-200 text-slate-700"
          ]}>
            {if(@dag.enabled, do: "Enabled", else: "Paused")}
          </span>

          <label class="cursor-pointer label dag-card__toggle">
            <input
              type="checkbox"
              name={"dag-enabling-toggle-#{@dag.id}"}
              checked={@dag.enabled}
              phx-click="toggle_enabled"
              phx-value-id={@dag.id}
              phx-target={@myself}
              class="toggle toggle-success"
            />
          </label>
        </div>
        <div class="dag-card__title-row">
          <h2 class="dag-card__title">
            <.link navigate={~p"/dags/#{@dag.name}/dashboard"}>{@dag.name}</.link>
          </h2>

          <div class="dag-card__actions">
            <button
              disabled={map_size(@dag_def.error) > 0}
              id={"trigger-dag-run-#{@id}"}
              phx-click="trigger_run"
              phx-value-id={@id}
              class="btn btn-primary"
            >
              Trigger
            </button>
          </div>
        </div>
      </section>

      <section class="dag-card__meta">
        <div class="dag-card__meta-item">
          <div class="dag-card__meta-label">Schedule</div>
          <div class="dag-card__meta-value">{@dag_def.options[:schedule]}</div>
        </div>
      </section>
    </div>
    """
  end
end
