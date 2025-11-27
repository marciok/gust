defmodule Gust.FileMonitor.Worker do
  @moduledoc false

  use GenServer
  alias Gust.DAG.Parser
  alias Gust.FileMonitor

  @impl true
  def init(%{dags_folder: folder, loader: loader}) do
    {:ok, watcher_pid} = FileMonitor.start_link(dirs: [folder], latency: 0)
    FileMonitor.watch(watcher_pid)
    events_queue = MapSet.new()

    {:ok, %{watcher_pid: watcher_pid, events_queue: events_queue, loader: loader}}
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  @impl true
  def handle_info({:file_event, _watcher_pid, {path, _events}}, %{events_queue: queue} = state) do
    if MapSet.member?(queue, path) do
      {:noreply, state}
    else
      Process.send_after(self(), {:check_queue, path}, delay())
      {:noreply, %{state | events_queue: MapSet.put(queue, path)}}
    end
  end

  def handle_info({:check_queue, path}, %{events_queue: queue, loader: loader} = state) do
    Parser.maybe_ex_file(path) |> broadcast_path(loader)

    {:noreply, %{state | events_queue: MapSet.delete(queue, path)}}
  end

  defp delay, do: Application.get_env(:gust, :file_reload_delay)

  defp broadcast_path(nil, _loader), do: nil

  defp broadcast_path(path, loader) do
    action = if File.exists?(path), do: "reload", else: "removed"
    dag_name = path |> Path.basename() |> Path.rootname()

    send(loader, {dag_name, Parser.parse(path), action})
  end
end
