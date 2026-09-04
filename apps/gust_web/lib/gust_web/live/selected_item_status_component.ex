defmodule GustWeb.SelectedItemStatusComponent do
  @moduledoc false

  use GustWeb, :live_component

  alias Gust.Flows.Task

  @impl true
  def update(%{tick: deadline}, %{assigns: %{retry_at: current_deadline}} = socket)
      when deadline == current_deadline do
    countdown = retry_countdown(deadline)

    socket =
      socket
      |> assign(:retry_countdown, countdown)
      |> schedule_retry_tick()

    {:ok, socket}
  end

  def update(%{tick: _stale_deadline}, socket), do: {:ok, socket}

  def update(assigns, socket) do
    retry_at = retry_deadline(assigns.status, assigns.item)
    deadline_changed? = retry_at != Map.get(socket.assigns, :retry_at)

    socket =
      socket
      |> assign(assigns)
      |> assign(:retry_at, retry_at)
      |> assign(:retry_countdown, retry_countdown(retry_at))

    socket = if deadline_changed?, do: schedule_retry_tick(socket), else: socket

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="status-badge-container"
      class={[
        @status == :retrying && @retry_countdown > 0 &&
          "tooltip tooltip-warning tooltip-left tooltip-open"
      ]}
      data-tip={
        if(@status == :retrying && @retry_countdown > 0,
          do: "#{@retry_countdown}s"
        )
      }
    >
      <.status_badge :if={@status} status={@status} data-testid="status-badge" />
    </div>
    """
  end

  defp retry_deadline(:retrying, %Task{retry_at: %DateTime{} = retry_at}), do: retry_at

  defp retry_deadline(:retrying, [%Task{} | _tail] = tasks) do
    retry_deadlines =
      for %Task{status: :retrying, retry_at: %DateTime{} = retry_at} <- tasks, do: retry_at

    case retry_deadlines do
      [] -> nil
      deadlines -> Enum.min_by(deadlines, &DateTime.to_unix(&1, :microsecond))
    end
  end

  defp retry_deadline(_status, _item), do: nil

  defp retry_countdown(%DateTime{} = deadline) do
    milliseconds = DateTime.diff(deadline, DateTime.utc_now(), :millisecond)
    if milliseconds > 0, do: div(milliseconds + 999, 1_000), else: 0
  end

  defp retry_countdown(_deadline), do: 0

  defp schedule_retry_tick(
         %{assigns: %{retry_countdown: countdown, retry_at: %DateTime{} = deadline}} = socket
       )
       when countdown > 0 do
    send_update_after(__MODULE__, %{id: socket.assigns.id, tick: deadline}, 1_000)
    socket
  end

  defp schedule_retry_tick(socket), do: socket
end
