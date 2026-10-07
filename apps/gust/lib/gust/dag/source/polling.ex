defmodule Gust.DAG.Source.Polling do
  @moduledoc """
  Generic polling monitor for sources that can't use OS file watching.

  Used by Git and Database sources to periodically reload and detect changes.
  """

  use GenServer

  @doc """
  Start a polling monitor that periodically calls the given load function
  and broadcasts changes to the loader_pid.

  The load function should return `%{dag_name => {:ok | :error, result}}`.
  """
  def start_link(loader_pid, load_fn, poll_interval_ms) do
    GenServer.start_link(__MODULE__, {loader_pid, load_fn, poll_interval_ms})
  end

  @doc """
  Pause the polling monitor.
  """
  def pause(server), do: GenServer.call(server, :pause)

  @doc """
  Resume the polling monitor.
  """
  def resume(server), do: GenServer.call(server, :resume)

  @doc """
  Return the monitor state.
  """
  def status(server), do: GenServer.call(server, :status)

  @impl true
  def init({loader_pid, load_fn, poll_interval_ms}) do
    {:ok,
     %{
       loader_pid: loader_pid,
       load_fn: load_fn,
       poll_interval_ms: poll_interval_ms,
       status: :running,
       timer_ref: schedule_next_tick(poll_interval_ms),
       last_state: %{}
     }}
  end

  @impl true
  def handle_call(:pause, _from, state) do
    if state.timer_ref, do: Process.cancel_timer(state.timer_ref)
    {:reply, :ok, %{state | status: :paused, timer_ref: nil}}
  end

  @impl true
  def handle_call(:resume, _from, state) do
    {:reply, :ok,
     %{state | status: :running, timer_ref: schedule_next_tick(state.poll_interval_ms)}}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, state.status, state}
  end

  @impl true
  def handle_info(:tick, %{status: :paused} = state) do
    {:noreply, %{state | timer_ref: nil}}
  end

  @impl true
  def handle_info(:tick, state) do
    current_state = state.load_fn.()

    detect_and_broadcast_changes(state.loader_pid, state.last_state, current_state)

    checksummed_state =
      current_state
      |> Enum.map(fn {name, result} ->
        {name, {result_checksum(result), result}}
      end)
      |> Map.new()

    {:noreply,
     %{
       state
       | last_state: checksummed_state,
         timer_ref: schedule_next_tick(state.poll_interval_ms)
     }}
  end

  defp schedule_next_tick(poll_interval_ms) do
    Process.send_after(self(), :tick, poll_interval_ms)
  end

  defp detect_and_broadcast_changes(loader_pid, last_state, current_state) do
    # Find new and updated DAGs
    Enum.each(current_state, fn {name, result} ->
      case Map.get(last_state, name) do
        nil ->
          # New DAG
          send(loader_pid, {name, result, "reload"})

        {old_checksum, _} ->
          new_checksum = result_checksum(result)

          old_checksum != new_checksum && send(loader_pid, {name, result, "reload"})
      end
    end)

    # Find removed DAGs
    Enum.each(last_state, fn {name, _} ->
      unless Map.has_key?(current_state, name) do
        send(loader_pid, {name, {:error, "DAG removed"}, "removed"})
      end
    end)
  end

  defp result_checksum({:ok, definition}) do
    definition |> inspect() |> sha256_hash()
  end

  defp result_checksum({:error, reason}) do
    reason |> inspect() |> sha256_hash()
  end

  defp sha256_hash(data) do
    :crypto.hash(:sha256, data) |> Base.encode16()
  end
end
