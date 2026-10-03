defmodule Gust.FileMonitor do
  @moduledoc """
  Helper API for file-system and source monitoring lifecycle controls.
  """
  @callback start_link(keyword()) :: GenServer.on_start()
  @callback watch(GenServer.server()) :: :ok

  @spec pause(GenServer.server() | nil) :: :ok | {:error, term()}
  def pause(server \\ nil)
  def pause(nil), do: {:error, :monitor_not_started}
  def pause(server), do: GenServer.call(server, :pause)

  @spec resume(GenServer.server() | nil) :: :ok | {:error, term()}
  def resume(server \\ nil)
  def resume(nil), do: {:error, :monitor_not_started}
  def resume(server), do: GenServer.call(server, :resume)

  @spec status(GenServer.server() | nil) :: :running | :paused | :stopped | {:error, term()}
  def status(server \\ nil)
  def status(nil), do: {:error, :monitor_not_started}
  def status(server), do: GenServer.call(server, :status)

  def watch(server_pid), do: impl().watch(server_pid)
  def start_link(args), do: impl().start_link(args)
  defp impl, do: Application.get_env(:gust, :file_monitor, Gust.FileMonitor.SystemFs)
end
