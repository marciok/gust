defmodule GustWeb.HealthCheckComponent do
  @moduledoc """
  Health check modal for the DAG dashboard.

  Owns everything about the check: which task or run is inspected, the async
  lookup through `Gust.DAG.Runner.Health`, and polling while the modal is open.
  The dashboard only renders this component and `trigger/1` buttons that
  target it.

  The next poll is scheduled only after a check returns, so slow checks never
  overlap. Each poll tick carries a token, and ticks from a closed modal or an
  older check are ignored.
  """

  use GustWeb, :live_component

  alias Gust.DAG.Runner.Health
  alias Gust.Flows.{Run, Task}
  alias Phoenix.LiveView.AsyncResult

  @component_id "health-check-component"

  @verdict_labels %{
    healthy: "Healthy",
    zombie: "Zombie",
    unknown: "Unknown",
    not_running: "Not running"
  }

  @verdict_classes %{
    healthy: "badge-success",
    zombie: "badge-error",
    unknown: "badge-warning",
    not_running: "badge-ghost"
  }

  @os_alive %{true => "alive", false => "dead"}
  @yes_no %{true => "yes", false => "no"}

  @process_info_fields [
    {:status, "Process status", nil, nil},
    {:current_function, "Current function", "font-mono break-all", nil},
    {:message_queue_len, "Message queue", nil, nil},
    {:memory, "Memory", nil, " bytes"},
    {:reductions, "Reductions", nil, nil}
  ]

  def component_id, do: @component_id

  @doc """
  What the header button inspects for the selected item: a single task or a
  whole run. Mapped groups have no target of their own; each mapped task row
  has its own trigger instead.
  """
  def target(%Task{} = task), do: {:task, task}
  def target(%Run{} = run), do: {:run, run}
  def target(_item), do: nil

  attr :id, :string, required: true
  attr :task_id, :integer, default: nil
  attr :label, :string, default: nil
  attr :class, :string, default: "btn-square"
  attr :icon_class, :string, default: "h-4 w-4"
  attr :rest, :global, default: %{"aria-label" => "Health check"}

  @doc "A button that opens the health check modal."
  def trigger(assigns) do
    assigns = assign(assigns, :target, "#" <> @component_id)

    ~H"""
    <button
      id={@id}
      type="button"
      phx-click="open"
      phx-target={@target}
      phx-value-task-id={@task_id}
      class={[
        "btn btn-outline btn-xs border-base-300 text-base-content/60",
        "hover:border-info hover:bg-transparent hover:text-info",
        @class
      ]}
      {@rest}
    >
      <.icon name="hero-cpu-chip" class={@icon_class} />{@label}
    </button>
    """
  end

  @impl true
  def mount(socket) do
    {:ok, assign(socket, health_check: nil, check_target: nil, tick_token: nil)}
  end

  @impl true
  def update(
        %{tick: token},
        %{assigns: %{tick_token: token, health_check: %AsyncResult{}}} = socket
      )
      when is_reference(token) do
    {:ok, start_check(socket)}
  end

  def update(%{tick: _token}, socket), do: {:ok, socket}

  def update(assigns, socket), do: {:ok, assign(socket, assigns)}

  @impl true
  def handle_event("open", %{"task-id" => task_id}, socket) do
    socket.assigns.selected_item
    |> mapped_target(task_id)
    |> open(socket)
  end

  def handle_event("open", _params, socket) do
    socket.assigns.selected_item
    |> target()
    |> open(socket)
  end

  def handle_event("refresh", _params, %{assigns: %{health_check: nil}} = socket),
    do: {:noreply, socket}

  def handle_event("refresh", _params, socket) do
    {:noreply,
     socket
     |> assign(:health_check, AsyncResult.loading(socket.assigns.health_check))
     |> start_check()}
  end

  def handle_event("close", _params, socket) do
    {:noreply,
     socket
     |> cancel_async(:health_check)
     |> assign(health_check: nil, check_target: nil, tick_token: nil)}
  end

  @impl true
  def handle_async(:health_check, _result, %{assigns: %{health_check: nil}} = socket),
    do: {:noreply, socket}

  def handle_async(:health_check, {:ok, report}, socket) do
    {:noreply,
     socket
     |> assign(:health_check, AsyncResult.ok(socket.assigns.health_check, report))
     |> schedule_tick()}
  end

  def handle_async(:health_check, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:health_check, AsyncResult.failed(socket.assigns.health_check, reason))
     |> schedule_tick()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <.modal
        :if={@health_check}
        async={@health_check}
        interval={interval()}
        myself={@myself}
      />
    </div>
    """
  end

  defp mapped_target([%Task{} | _rest] = tasks, task_id) do
    case Enum.find(tasks, &(to_string(&1.id) == to_string(task_id))) do
      %Task{} = task -> {:task, task}
      nil -> nil
    end
  end

  defp open(nil, socket), do: {:noreply, socket}

  defp open(check_target, socket) do
    {:noreply,
     socket
     |> cancel_async(:health_check)
     |> assign(check_target: check_target, health_check: AsyncResult.loading())
     |> start_check()}
  end

  defp start_check(%{assigns: %{check_target: check_target}} = socket) do
    socket
    |> assign(:tick_token, nil)
    |> start_async(:health_check, fn -> inspect_target(check_target) end)
  end

  defp inspect_target({:task, task}), do: Health.inspect_task(task)
  defp inspect_target({:run, run}), do: Health.inspect_run(run)

  defp schedule_tick(socket) do
    token = make_ref()
    send_update_after(__MODULE__, %{id: socket.assigns.id, tick: token}, interval())
    assign(socket, :tick_token, token)
  end

  defp interval, do: Application.get_env(:gust_web, :health_check_interval, 5_000)

  attr :async, AsyncResult, required: true
  attr :interval, :integer, required: true
  attr :myself, :any, required: true

  defp modal(assigns) do
    ~H"""
    <dialog
      id="health-modal"
      class="modal modal-open"
      phx-window-keydown="close"
      phx-key="escape"
      phx-target={@myself}
    >
      <div class="modal-box max-w-3xl">
        <div class="flex items-center justify-between gap-2">
          <h3 id="health-modal-title" class="flex items-center gap-2 text-lg font-semibold">
            <.icon name="hero-cpu-chip" class="h-5 w-5 text-base-content/60" /> Health check
          </h3>
          <div class="flex gap-2">
            <button
              id="health-refresh"
              type="button"
              class="btn btn-sm btn-soft"
              phx-click="refresh"
              phx-target={@myself}
              disabled={@async.loading}
            >
              <.icon
                name="hero-arrow-path"
                class={if(@async.loading, do: "h-4 w-4 animate-spin", else: "h-4 w-4")}
              /> Refresh
            </button>
            <button
              id="health-close"
              type="button"
              class="btn btn-sm btn-ghost"
              phx-click="close"
              phx-target={@myself}
              aria-label="Close"
            >
              <.icon name="hero-x-mark" class="h-4 w-4" />
            </button>
          </div>
        </div>

        <p :if={@async.loading && is_nil(@async.result)} id="health-loading" class="py-6 text-sm">
          Checking processes…
        </p>

        <div :if={@async.failed} id="health-failed" role="alert" class="alert alert-warning mt-4">
          <span>The health check could not complete: {inspect(@async.failed)}</span>
        </div>

        <.report :if={@async.result} report={@async.result} interval={@interval} />
      </div>
      <div class="modal-backdrop" phx-click="close" phx-target={@myself}></div>
    </dialog>
    """
  end

  attr :report, :map, required: true
  attr :interval, :integer, required: true

  defp report(assigns) do
    assigns =
      assign(assigns,
        verdict_labels: @verdict_labels,
        verdict_classes: @verdict_classes,
        os_alive: @os_alive,
        yes_no: @yes_no,
        process_info_fields: @process_info_fields
      )

    ~H"""
    <div id="health-report" class="mt-4 flex flex-col gap-4">
      <div :if={@report.error} id="health-error" role="alert" class="alert alert-warning">
        <span>Owner node could not be checked: {@report.error}</span>
      </div>

      <section id="health-run" class="flex flex-col gap-2">
        <h4 class="text-sm font-semibold text-base-content/75">Run {@report.run.id}</h4>
        <dl class="grid grid-cols-[max-content_1fr] gap-x-4 gap-y-1 text-sm">
          <dt class="text-base-content/60">Status</dt>
          <dd>{@report.run.status}</dd>
          <dt class="text-base-content/60">Claimed by</dt>
          <dd id="health-claimed-by">{@report.run.claimed_by || "local (unclaimed)"}</dd>
          <dt class="text-base-content/60">Node connected</dt>
          <dd id="health-node-connected">{@yes_no[@report.run.node_connected]}</dd>
          <dt class="text-base-content/60">Claim expires</dt>
          <dd>{format_time(@report.run.claim_expires_at)}</dd>
          <dt class="text-base-content/60">DAG worker</dt>
          <dd id="health-dag-worker">{process_summary(@report.run.dag_worker, @report.error)}</dd>
        </dl>
      </section>

      <section id="health-tasks" class="flex flex-col gap-3">
        <p :if={@report.tasks == []} id="health-no-tasks" class="text-sm text-base-content/60">
          No running tasks in this run.
        </p>
        <div
          :for={task <- @report.tasks}
          id={"health-task-#{task.id}"}
          class="rounded-box border border-base-300 p-3"
        >
          <div class="flex items-center justify-between gap-2">
            <span class="font-medium text-sm">
              {task.name}<span :if={task.map_index}> [{task.map_index}]</span>
            </span>
            <span
              id={"health-verdict-#{task.id}"}
              data-verdict={task.verdict}
              class={["badge badge-sm", @verdict_classes[task.verdict]]}
            >
              {@verdict_labels[task.verdict]}
            </span>
          </div>
          <dl class="mt-2 grid grid-cols-[max-content_1fr] gap-x-4 gap-y-1 text-xs">
            <dt class="text-base-content/60">DB status</dt>
            <dd>{task.status}</dd>
            <dt class="text-base-content/60">Registry key</dt>
            <dd class="font-mono">{task.registry_key}</dd>
            <dt class="text-base-content/60">Task worker</dt>
            <dd id={"health-task-worker-#{task.id}"}>
              {process_summary(task.process, @report.error)}
            </dd>
            <%= if task.process && task.process.info do %>
              <%= for {key, label, class, unit} <- @process_info_fields do %>
                <dt class="text-base-content/60">{label}</dt>
                <dd id={"health-info-#{key}-#{task.id}"} class={class}>
                  {task.process.info[key]}{unit}
                </dd>
              <% end %>
            <% end %>
            <%= if task.process && task.process.os_process do %>
              <dt class="text-base-content/60">OS process</dt>
              <dd id={"health-os-process-#{task.id}"}>
                {task.process.os_process.os_pid} ({@os_alive[task.process.os_process.alive]})
              </dd>
            <% end %>
          </dl>
        </div>
      </section>

      <p id="health-checked-at" class="text-xs text-base-content/60">
        Checked at {format_time(@report.checked_at)} · refreshes every {div(@interval, 1000)}s
      </p>
    </div>
    """
  end

  defp process_summary(_process, error) when not is_nil(error), do: "unknown"
  defp process_summary(nil, _error), do: "not found"
  defp process_summary(%{pid: pid, alive: true}, _error), do: "#{pid} (alive)"
  defp process_summary(%{pid: pid}, _error), do: "#{pid} (dead)"

  defp format_time(nil), do: "—"
  defp format_time(%DateTime{} = time), do: Calendar.strftime(time, "%Y-%m-%d %H:%M:%S UTC")
end
