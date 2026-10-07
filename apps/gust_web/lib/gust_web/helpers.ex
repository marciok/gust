defmodule GustWeb.LiveView.Helpers do
  @moduledoc """
  Helper functions for managing the DAG monitor's state in LiveView.
  """
  import Phoenix.LiveView.Utils, only: [put_flash: 3]

  def resume(socket, source_id \\ nil) do
    case Gust.DAG.Source.monitor_resume(source_id) do
      :ok ->
        socket

      {:error, reason} ->
        put_flash(
          socket,
          :error,
          "Failed to resume #{source_id || "DAG monitor"}: #{inspect(reason)}"
        )
    end
  end

  def pause(socket, source_id \\ nil) do
    case Gust.DAG.Source.monitor_pause(source_id) do
      :ok ->
        socket

      {:error, reason} ->
        put_flash(
          socket,
          :error,
          "Failed to pause #{source_id || "DAG monitor"}: #{inspect(reason)}"
        )
    end
  end
end
