defmodule Gust.DAG.Source do
  @moduledoc """
  Behavior for pluggable DAG source implementations.

  A DAG source defines where DAGs come from (filesystem, git repo, database, etc.)
  and how to monitor them for changes.

  Monitoring can be paused or resumed while the app is running. The source monitor
  process typically exposes `:pause`, `:resume`, and `:status` through `GenServer.call/2`.
  """
  alias Gust.DAG.Source.Config

  @type monitor_status :: :running | :paused | :stopped

  @doc false
  def config, do: Config.read()

  @doc false
  def module, do: Config.module_name()

  @doc """
  Pause automatic monitoring for a DAG source monitor process.
  """
  @spec monitor_pause(pid() | nil) :: :ok | {:error, term()}
  def monitor_pause(nil), do: {:error, :monitor_not_started}

  def monitor_pause(pid) when is_pid(pid), do: GenServer.call(pid, :pause)
  def monitor_pause(other), do: {:error, {:invalid_monitor, other}}

  @doc """
  Resume automatic monitoring for a DAG source monitor process.
  """
  @spec monitor_resume(pid() | nil) :: :ok | {:error, term()}
  def monitor_resume(nil), do: {:error, :monitor_not_started}

  def monitor_resume(pid) when is_pid(pid), do: GenServer.call(pid, :resume)
  def monitor_resume(other), do: {:error, {:invalid_monitor, other}}

  @doc """
  Return the current monitor state for a DAG source monitor process.
  """
  @spec monitor_status(pid() | nil) :: monitor_status() | {:error, term()}
  def monitor_status(nil), do: {:error, :monitor_not_started}

  def monitor_status(pid) when is_pid(pid), do: GenServer.call(pid, :status)
  def monitor_status(other), do: {:error, {:invalid_monitor, other}}

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
  Get the name of the source implementation for logging/debugging.
  """
  @callback name() :: String.t()

  @optional_callbacks load: 1
end
