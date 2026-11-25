defmodule GustWeb.DagLive.Dashboard.UpdateBatcher do
  @moduledoc """
  Coalesces dashboard updates by run and task within a refresh interval.

  State and the flush timer belong to the LiveView process. The caller handles
  `:flush_run_updates` by calling `flush/2` and supplies the reload callback,
  which receives the socket, run ID, and a set of task IDs. A nil task ID
  represents an update to the run itself.
  """

  import Phoenix.Component, only: [assign: 3]

  def init(socket), do: assign(socket, :pending_run_updates, %{})

  def enqueue(socket, run_id, task_id, reload) do
    case refresh_interval() do
      0 ->
        reload.(socket, run_id, MapSet.new([task_id]))

      interval ->
        pending = socket.assigns.pending_run_updates
        if pending == %{}, do: Process.send_after(self(), :flush_run_updates, interval)

        updates = Map.update(pending, run_id, MapSet.new([task_id]), &MapSet.put(&1, task_id))
        assign(socket, :pending_run_updates, updates)
    end
  end

  def flush(socket, reload) do
    socket =
      Enum.reduce(socket.assigns.pending_run_updates, socket, fn {run_id, task_ids}, acc ->
        reload.(acc, run_id, task_ids)
      end)

    init(socket)
  end

  def drop(socket, run_ids) do
    assign(socket, :pending_run_updates, Map.drop(socket.assigns.pending_run_updates, run_ids))
  end

  defp refresh_interval, do: Application.get_env(:gust_web, :dashboard_refresh_interval, 300)
end
