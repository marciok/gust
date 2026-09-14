defmodule Gust.FileMonitor.Worker do
  @moduledoc """
  Wraps the active DAG source monitor and exposes lifecycle controls for it.
  """

  use GenServer
  require Logger

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @spec pause() :: :ok | {:error, term()}
  def pause, do: GenServer.call(__MODULE__, :pause)

  @spec resume() :: :ok | {:error, term()}
  def resume, do: GenServer.call(__MODULE__, :resume)

  @spec status() :: :running | :paused | :stopped | {:error, term()}
  def status, do: GenServer.call(__MODULE__, :status)

  @impl true
  def init(%{loader: loader} = args) do
    source = get_source()
    persisted_status = read_monitor_status()

    case source.monitor(loader, args) do
      {:ok, monitor_pid} ->
        state = %{monitor_pid: monitor_pid, source: source, loader: loader, status: :running}

        state =
          with :paused <- persisted_status,
            :ok <- Gust.DAG.Source.monitor_pause(monitor_pid) do
              Logger.warning("DAGs #{source.name()} monitor is paused on startup due to persisted state")
              %{state | status: :paused}
          else
            _ ->
              Logger.info("Started #{source.name()} monitor for DAG changes")
              state
          end

        persist_monitor_status(state.status)
        {:ok, state}

      {:error, reason} ->
        {:stop, "Failed to start DAG source monitor: #{inspect(reason)}"}
    end
  end

  @impl true
  def handle_call(:pause, _from, state) do
    reply = Gust.DAG.Source.monitor_pause(state.monitor_pid)
    new_status = if reply == :ok, do: :paused, else: state.status
    persist_monitor_status(new_status)
    {:reply, reply, %{state | status: new_status}}
  end

  @impl true
  def handle_call(:resume, _from, state) do
    reply = Gust.DAG.Source.monitor_resume(state.monitor_pid)
    new_status = if reply == :ok, do: :running, else: state.status
    persist_monitor_status(new_status)
    {:reply, reply, %{state | status: new_status}}
  end

  @impl true
  def handle_call(:status, _from, state) do
    reply = Gust.DAG.Source.monitor_status(state.monitor_pid)
    new_status = if reply in [:running, :paused, :stopped], do: reply, else: state.status
    persist_monitor_status(new_status)
    {:reply, reply, %{state | status: new_status}}
  end

  @impl true
  def handle_info(msg, state) do
    if state.monitor_pid && is_pid(state.monitor_pid) do
      send(state.monitor_pid, msg)
    end

    {:noreply, state}
  end

  defp get_source do
    Gust.DAG.Source.module()
  end

  defp read_monitor_status do
    path = monitor_status_path()

    case File.read(path) do
      {:ok, status} ->
        status
        |> String.trim()
        |> String.split(~r/\s+/, trim: true)
        |> List.last()
        |> case do
          "paused" -> :paused
          "running" -> :running
          "stopped" -> :stopped
          _ -> :running
        end

      {:error, _reason} ->
        :running
    end
  end

  defp persist_monitor_status(status) when status in [:running, :paused, :stopped] do
    path = monitor_status_path()
    dir = Path.dirname(path)
    File.mkdir_p!(dir)
    File.write!(path, "#{DateTime.utc_now()} #{status}")
    :ok
  end

  defp persist_monitor_status(_status), do: :ok

  defp monitor_status_path do
    Application.get_env(
      :gust,
      :dag_source_monitor_status_path,
      Path.join(System.tmp_dir!(), "gust-dag-source-monitor-status.txt")
    )
  end
end
