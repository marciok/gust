defmodule Gust.PGNotifier do
  @moduledoc false

  @callback start_link(keyword()) :: GenServer.on_start()
  @callback listen(GenServer.server(), String.t()) :: {:ok, reference()}
  @callback enqueue(term()) :: term()

  def start_link(opts), do: impl().start_link(opts)
  def listen(server, channel), do: impl().listen(server, channel)
  def enqueue(run), do: impl().enqueue(run)

  defp impl do
    Application.get_env(:gust, :pg_notifier, Gust.PGNotifier.Postgrex)
  end
end
