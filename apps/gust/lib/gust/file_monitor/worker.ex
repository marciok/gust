defmodule Gust.FileMonitor.Worker do
  @moduledoc """
  Wraps the active DAG source monitors and exposes lifecycle controls for them.
  """

  use GenServer

  alias Gust.DAG.Source
  alias Gust.DAG.Source.Config
  alias Gust.DAG.Source.MonitorState
  alias Gust.PubSub

  def start_link(args) do
    id = id(args)
    GenServer.start_link(__MODULE__, args, name: via_tuple(id))
  end

  def child_spec(args) do
    id = id(args)

    %{
      id: {:file_monitor_worker, id},
      start: {__MODULE__, :start_link, [args]},
      restart: :permanent,
      shutdown: 5000,
      type: :worker
    }
  end

  @spec pause(term() | nil) :: :ok | {:error, term()}
  def pause(id \\ nil), do: call(id, :pause)

  @spec resume(term() | nil) :: :ok | {:error, term()}
  def resume(id \\ nil), do: call(id, :resume)

  @spec status(term() | nil) :: :running | :paused | :stopped | {:error, term()}
  def status(id \\ nil), do: call(id, :status)

  defp call(id, request) do
    registry_id = id(id)

    case Registry.lookup(Gust.Registry, registry_id) do
      [{pid, _}] when is_pid(pid) -> GenServer.call(pid, request)
      [] -> {:error, {:monitor_not_started, registry_id}}
    end
  end

  @impl true
  def init(%{loader: loader} = args) do
    id = id(args)
    monitor_specs = monitor_specs(loader, id)

    {:ok,
     %{
       monitor_specs: Map.new(Enum.map(monitor_specs, &{&1.id, &1})),
       loader: loader,
       status: :running
     }}
  rescue
    e in ArgumentError ->
      {:stop, e.message}
  end

  defp monitor_specs(loader, id) do
    Config.read()
    |> Enum.filter(&(source_id(&1) == id))
    |> case do
      [] -> raise ArgumentError, "No DAG source configured with id #{inspect(id)}"
      configs -> Enum.map(configs, &start_monitor(&1, loader, id))
    end
  end

  defp source_id(config), do: Map.get(config, :id) || Map.get(config, "id")

  defp start_monitor(config, loader, id) do
    config_id = Map.get(config, :id) || Map.get(config, "id")
    source_module = Config.source_module(config)
    status = read_monitor_status(source_module, config_id)

    config = Map.put(config, :status, status)

    case source_module.monitor(loader, config) do
      {:ok, monitor_pid} ->
        monitor_pid = resume_paused_monitor(monitor_pid, status)

        %{id: id, module: source_module, monitor_pid: monitor_pid, config: config, status: status}

      {:error, reason} ->
        raise ArgumentError,
              "Failed to start DAG source monitor for #{source_module}: #{inspect(reason)}"
    end
  end

  defp resume_paused_monitor(monitor_pid, :paused) do
    :ok = Source.monitor_pause(monitor_pid)
    monitor_pid
  end

  defp resume_paused_monitor(monitor_pid, _status), do: monitor_pid

  @impl true
  def handle_call(:pause, _from, state) do
    reply =
      state.monitor_specs
      |> Map.values()
      |> Enum.reduce_while(:ok, fn %{monitor_pid: pid, id: id, module: module}, :ok ->
        case Source.monitor_pause(pid) do
          :ok ->
            persist_monitor_status(module, id, :paused)
            {:cont, :ok}

          {:error, _} = error ->
            {:halt, error}
        end
      end)

    new_status = if reply == :ok, do: :paused, else: state.status

    Enum.each(state.monitor_specs, fn {_id, %{id: source_id}} ->
      PubSub.broadcast_source_status(source_id, new_status)
    end)

    {:reply, reply, %{state | status: new_status}}
  end

  @impl true
  def handle_call(:resume, _from, state) do
    reply =
      state.monitor_specs
      |> Map.values()
      |> Enum.reduce_while(:ok, fn %{monitor_pid: pid, id: id, module: module}, :ok ->
        case Source.monitor_resume(pid) do
          :ok ->
            persist_monitor_status(module, id, :running)
            {:cont, :ok}

          {:error, _} = error ->
            {:halt, error}
        end
      end)

    new_status = if reply == :ok, do: :running, else: state.status

    Enum.each(state.monitor_specs, fn {_id, %{id: source_id}} ->
      PubSub.broadcast_source_status(source_id, new_status)
    end)

    {:reply, reply, %{state | status: new_status}}
  end

  @impl true
  def handle_call(:status, _from, state) do
    replies =
      state.monitor_specs
      |> Map.values()
      |> Enum.map(&Source.monitor_status(&1.monitor_pid))

    reply =
      cond do
        Enum.all?(replies, &(&1 == :running)) -> :running
        Enum.all?(replies, &(&1 == :paused)) -> :paused
        Enum.all?(replies, &(&1 in [:running, :paused, :stopped])) -> :stopped
        true -> state.status
      end

    new_status = if reply in [:running, :paused, :stopped], do: reply, else: state.status

    Enum.each(state.monitor_specs, fn {_id, %{id: source_id, module: source_module}} ->
      persist_monitor_status(source_module, source_id, new_status)
    end)

    {:reply, reply, %{state | status: new_status}}
  end

  @impl true
  def handle_info(msg, state) do
    Enum.each(state.monitor_specs, fn {_id, %{monitor_pid: pid}} ->
      if pid && is_pid(pid), do: send(pid, msg)
    end)

    {:noreply, state}
  end

  defp read_monitor_status(source_module, source_id) do
    MonitorState.read(source_id, source_module)
  end

  defp persist_monitor_status(source_module, source_id, status)
       when status in [:running, :paused, :stopped] do
    MonitorState.save(source_id, source_module, status)
    :ok
  end

  defp persist_monitor_status(_source_module, _source_id, _status), do: :ok

  defp via_tuple(id), do: {:via, Registry, {Gust.Registry, id}}

  defp id(%{} = args) do
    Map.get(args, :id) || Map.get(args, "id") ||
      raise(ArgumentError, "FileMonitor.Worker requires a configured :id")
  end

  defp id(id) when is_binary(id) or is_atom(id), do: id
  defp id(value), do: raise(ArgumentError, "Invalid source id '#{inspect(value)}'")
end
