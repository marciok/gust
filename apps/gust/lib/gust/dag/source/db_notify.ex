defmodule Gust.DAG.Source.Database.Notify do
  @moduledoc """
  DAG source that listens for database notifications to trigger reloads.

  Uses Postgrex.Notifications to subscribe to a specific channel and detects changes
  in the DAG definitions stored in the database.

  ## Implementation Details

  - Subscribes to the "gust-dag-source-changes" PostgreSQL notification channel
  - Maintains checksums of DAG definitions using SHA256 hashing to detect changes
  - Compares current state with last known state to identify new, modified, or removed DAGs
  - Broadcasts change notifications to the loader process for each affected DAG
  - Tracks state as `{name, {checksum, result}}` pairs to enable efficient diffing
  - Sends messages with format: `{name, result, action}` where action is "reload" or "removed"

  To keep time-window filters (`start_time`/`end_time`) accurate even when no
  write notifications are emitted, it also performs periodic reconciliation.
  """

  use GenServer

  @channel "gust-dag-source-changes"

  def start_link(loader_pid, load_fn, poll_interval_ms) do
    GenServer.start_link(__MODULE__, {loader_pid, load_fn, poll_interval_ms})
  end

  @impl true
  def init({loader_pid, load_fn, poll_interval_ms}) do
    {:ok, connection} = Postgrex.Notifications.start_link(repo_opts())
    {:ok, _ref} = Postgrex.Notifications.listen(connection, @channel)

    last_state =
      load_fn.()
      |> normalize_current_state()
      |> normalize_state()

    {:ok,
     %{
       loader_pid: loader_pid,
       load_fn: load_fn,
       poll_interval_ms: poll_interval_ms,
       status: :running,
       timer_ref: schedule_next_tick(poll_interval_ms),
       connection: connection,
       last_state: last_state
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
  def handle_info({:notification, _pid, _ref, @channel, _payload}, %{status: :paused} = state) do
    {:noreply, state}
  end

  @impl true
  def handle_info({:notification, _pid, _ref, @channel, _payload}, state) do
    current_state = normalize_current_state(state.load_fn.())
    detect_and_broadcast_changes(state.loader_pid, state.last_state, current_state)

    {:noreply, %{state | last_state: normalize_state(current_state)}}
  end

  @impl true
  def handle_info(:tick, %{status: :paused} = state) do
    {:noreply, state}
  end

  @impl true
  def handle_info(:tick, state) do
    current_state = normalize_current_state(state.load_fn.())
    detect_and_broadcast_changes(state.loader_pid, state.last_state, current_state)

    {:noreply,
     %{
       state
       | last_state: normalize_state(current_state),
         timer_ref: schedule_next_tick(state.poll_interval_ms)
     }}
  end

  defp normalize_current_state(%{success: success, error: error}) do
    success_entries = Enum.map(success, fn {name, value} -> {name, {:ok, value}} end)
    error_entries = Enum.map(error, fn {name, reason} -> {name, {:error, reason}} end)

    Map.new(success_entries ++ error_entries)
  end

  defp normalize_current_state(map) when is_map(map), do: map
  defp normalize_current_state(_), do: %{}

  defp repo_opts do
    Gust.Repo.config()
    |> Keyword.delete(:name)
  end

  defp schedule_next_tick(poll_interval_ms) do
    Process.send_after(self(), :tick, poll_interval_ms)
  end

  defp detect_and_broadcast_changes(loader_pid, last_state, current_state) do
    Enum.each(current_state, fn {name, result} ->
      case Map.get(last_state, name) do
        nil ->
          send(loader_pid, {name, result, "reload"})

        {old_checksum, _} ->
          new_checksum = result_checksum(result)
          old_checksum != new_checksum && send(loader_pid, {name, result, "reload"})
      end
    end)

    Enum.each(last_state, fn {name, _} ->
      unless Map.has_key?(current_state, name) do
        send(loader_pid, {name, {:error, "DAG removed"}, "removed"})
      end
    end)
  end

  defp normalize_state(current_state) do
    current_state
    |> Enum.map(fn {name, result} ->
      {name, {result_checksum(result), result}}
    end)
    |> Map.new()
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
