defmodule Gust.FileMonitor do
  @moduledoc false
  @callback start_link(keyword()) :: GenServer.on_start()
  @callback watch(GenServer.server()) :: :ok

  def watch(server_pid), do: impl().watch(server_pid)
  def start_link(args), do: impl().start_link(args)
  defp impl, do: Application.get_env(:gust, :file_monitor, Gust.FileMonitor.SystemFs)
end
