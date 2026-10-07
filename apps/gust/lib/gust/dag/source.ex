defmodule Gust.DAG.Source do
  @moduledoc """
  Behavior for pluggable DAG source implementations.

  A DAG source defines where DAGs come from (filesystem, git repo, database, etc.)
  and how to monitor them for changes.

  Monitoring can be paused or resumed while the app is running. The source monitor
  process typically exposes `:pause`, `:resume`, and `:status` through `GenServer.call/2`.
  """
  alias Gust.DAG.Source.Config

  @optional_callbacks load: 1, validate: 2

  @doc """
  Get the name of the source implementation for logging/debugging.
  """
  @callback name() :: String.t()

  @doc """
  Load all DAG definitions from the source.

  Takes an optional effective_time parameter (defaults to DateTime.utc_now())
  for DAG versioning and time-based filtering.

  Returns a map with separate lists of successful and failed DAG loads.
  On source-level errors (can't connect to DB, can't clone repo, etc), returns {:error, reason}.
  """
  @callback load() ::
              %{success: [{String.t(), any()}], error: [{String.t(), any()}]} | {:error, any()}
  @callback load(effective_time :: nil | DateTime.t()) ::
              %{success: [{String.t(), any()}], error: [{String.t(), any()}]} | {:error, any()}

  @doc """
  Start monitoring the source for changes.

  When the source changes (files modified, repo updated, DB records changed),
  the monitor should send messages to `loader_pid` in the format:
  `{dag_name, parse_result, action}`
  where `action` is "reload" or "removed".

  Returns `{:ok, monitor_pid}` or `{:error, reason}`.
  """
  @callback monitor(loader_pid :: pid(), config :: map()) :: {:ok, pid()} | {:error, term()}

  @doc """
  Validates source-specific startup requirements (e.g. a folder exists).

  Optional. Sources without startup requirements can omit it.
  """
  @callback validate(env :: String.t(), config :: map()) :: :ok | {:error, String.t()}

  @typedoc "Status of the DAG source monitor process."
  @type monitor_status :: :running | :paused | :stopped

  @doc """
  Validates every configured source at startup, raising with the source id on failure.
  """
  @spec validate_all!(String.t() | atom(), [map()]) :: :ok
  def validate_all!(env, source_configs \\ Config.read()) do
    Enum.each(source_configs, fn config ->
      module = Config.source_module(config)

      with true <- Code.ensure_loaded?(module),
           true <- function_exported?(module, :validate, 2),
           :ok <- module.validate(env, config) do
        :ok
      else
        false ->
          :ok

        {:error, reason} ->
          raise ArgumentError, "DAG source #{inspect(config)}: #{reason}"
      end
    end)
  end

  @doc false
  def config do
    case Config.read() do
      [%{} = source | _] -> Map.to_list(source)
      _ -> []
    end
  end

  @doc false
  def configs, do: Config.read()

  @doc false
  def module(id) do
    case Enum.find(Config.read(), &(&1.id == id || &1["id"] == id)) do
      nil -> nil
      source -> Config.source_module(source)
    end
  end

  @doc false
  def modules, do: Config.module_names()

  @doc """
  Pause automatic monitoring for a DAG source monitor process.
  """
  @spec monitor_pause(pid() | term() | nil) :: :ok | {:error, term()}
  def monitor_pause(nil), do: {:error, :monitor_not_started}
  def monitor_pause(id) when is_pid(id), do: GenServer.call(id, :pause)

  def monitor_pause(id) when is_binary(id) or is_atom(id) do
    case Registry.lookup(Gust.Registry, id) do
      [{pid, _}] when is_pid(pid) -> GenServer.call(pid, :pause)
      [] -> {:error, {:monitor_not_started, id}}
    end
  end

  def monitor_pause(other), do: {:error, {:invalid_monitor, other}}

  @doc """
  Resume automatic monitoring for a DAG source monitor process.
  """
  @spec monitor_resume(pid() | term() | nil) :: :ok | {:error, term()}
  def monitor_resume(nil), do: {:error, :monitor_not_started}
  def monitor_resume(pid) when is_pid(pid), do: GenServer.call(pid, :resume)

  def monitor_resume(id) when is_binary(id) or is_atom(id) do
    case Registry.lookup(Gust.Registry, id) do
      [{pid, _}] when is_pid(pid) -> GenServer.call(pid, :resume)
      [] -> {:error, {:monitor_not_started, id}}
    end
  end

  def monitor_resume(other), do: {:error, {:invalid_monitor, other}}

  @doc """
  Return the current monitor state for a DAG source monitor process.
  """
  @spec monitor_status(pid() | term() | nil) :: monitor_status() | {:error, term()}
  def monitor_status(nil), do: {:error, :monitor_not_started}
  def monitor_status(pid) when is_pid(pid), do: GenServer.call(pid, :status)

  def monitor_status(id) when is_binary(id) or is_atom(id) do
    case Registry.lookup(Gust.Registry, id) do
      [{pid, _}] when is_pid(pid) -> GenServer.call(pid, :status)
      [] -> {:error, {:monitor_not_started, id}}
    end
  end

  def monitor_status(other), do: {:error, {:invalid_monitor, other}}
end
