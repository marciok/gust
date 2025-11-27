defmodule GustWeb.DagSummaryComponent do
  @moduledoc false
  use GustWeb, :live_component
  alias Gust.DAG.RunRestarter
  alias Gust.Flows

  @impl true
  def handle_event("toggle_enabled", %{"id" => dag_id}, socket) do
    {:ok, dag} = Flows.get_dag!(dag_id) |> Flows.toggle_enabled()

    if dag.enabled do
      RunRestarter.restart_enqueued(dag.id)
    end

    {:noreply, socket |> assign(:dag, dag)}
  end

  defp format_error(%CompileError{file: _file, description: description, line: _line}),
    do: description

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-white rounded shadow-sm overflow-hidden mb-4">
      <div :if={map_size(@dag_def.error) > 0} class="alert alert-error shadow-lg mb-4" role="alert">
        <span id={"dag-error-#{@id}"}>
          <strong>{format_error(@dag_def.error)}</strong>
        </span>
      </div>

      <div
        :if={length(@dag_def.messages) > 0}
        class="bg-warning text-warning-content rounded-xl p-4 shadow-md space-y-2"
      >
        <h2 class="text-md font-semibold">Warnings</h2>
        <ul class="list-disc list-inside text-sm">
          <%= for message <- @dag_def.messages do %>
            <li>{message.message}</li>
          <% end %>
        </ul>
      </div>
      <div class="p-3 border-b bg-gray-50">
        <div class="flex justify-between items-center">
          <div>
            <div class="flex items-center mb-5">
              <label class="cursor-pointer label">
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
            <h2 class="font-semibold text-gray-800 underline">
              <.link navigate={~p"/dags/#{@dag.name}/runs"}>{@dag.name}</.link>
            </h2>
          </div>

          <div class="flex gap-2 items-center"></div>
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

      <div class="grid grid-cols-2 md:grid-cols-3 text-xs">
        <div class="p-3 border-r border-b">
          <div class="text-gray-500 font-medium">Schedule</div>
          <div class="mt-1 text-gray-800">{@dag_def.options[:schedule]}</div>
        </div>
      </div>
    </div>
    """
  end
end
