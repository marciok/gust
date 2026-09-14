defmodule Gust.DAG.Source.Folder.Monitor do
  @moduledoc """
  Monitors a folder for file changes and notifies the loader process.

  Uses a GenServer to track file events and maintain a queue of changes.
  Supports pausing and resuming the monitoring process.

  ## Features

    * File event detection via file watcher integration
    * Debounced event processing with configurable delay (default: 1000ms)
    * Event queue management using MapSet for deduplication
    * Dynamic pause/resume control via call-based interface
    * Status queries to check monitoring state
    * Adapter-based file type routing for specialized parsing

  ## Options

    * `:file_reload_delay` - Milliseconds to wait before processing queued events (default: 1000)

  ## Usage

    start_link(watcher_pid, loader_pid, %{path: "/some/folder"})
    GenServer.call(pid, :pause)
    GenServer.call(pid, :resume)
    GenServer.call(pid, :status)
  """

  use GenServer

  alias Gust.DAG.Adapter
  alias Gust.DAG.Folder
  alias Gust.DAG.Parser

  def start_link(watcher_pid, loader_pid, folder) do
    GenServer.start_link(__MODULE__, {watcher_pid, loader_pid, folder})
  end

  @impl true
  def init({watcher_pid, loader_pid, folder}) do
    state = %{
      watcher_pid: watcher_pid,
      loader_pid: loader_pid,
      events_queue: MapSet.new(),
      folder: folder,
      status: :running
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:pause, _from, state) do
    {:reply, :ok, %{state | status: :paused}}
  end

  @impl true
  def handle_call(:resume, _from, state) do
    {:reply, :ok, %{state | status: :running}}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, state.status, state}
  end

  @impl true
  def handle_info({:file_event, _watcher_pid, {path, _events}}, %{status: :paused} = state) do
    {:noreply, %{state | events_queue: MapSet.delete(state.events_queue, path)}}
  end

  @impl true
  def handle_info({:file_event, _watcher_pid, {path, _events}}, state) do
    queue =
      if MapSet.member?(state.events_queue, path) do
        state.events_queue
      else
        Process.send_after(self(), {:check_queue, path}, delay())
        MapSet.put(state.events_queue, path)
      end

    {:noreply, %{state | events_queue: queue}}
  end

  @impl true
  def handle_info({:check_queue, path}, %{status: :paused} = state) do
    {:noreply, %{state | events_queue: MapSet.delete(state.events_queue, path)}}
  end

  @impl true
  def handle_info({:check_queue, path}, state) do
    if adapter = adapter_for_path(path) do
      broadcast_path(path, state.loader_pid, adapter)
    end

    queue = MapSet.delete(state.events_queue, path)
    {:noreply, %{state | events_queue: queue}}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp adapter_for_path(path) do
    extension = Path.extname(path)
    Adapter.parser_for_extension(extension)
  end

  defp broadcast_path(path, loader_pid, adapter) do
    action = Folder.action(path)
    dag_name = Folder.dag_name(path)

    send(loader_pid, {dag_name, Parser.parse(adapter, path), action})
  end

  defp delay, do: Application.get_env(:gust, :file_reload_delay, 1_000)
end
