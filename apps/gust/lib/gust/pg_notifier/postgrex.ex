defmodule Gust.PGNotifier.Postgrex do
  @moduledoc false

  alias Ecto.Adapters.SQL
  alias Gust.Flows
  alias Gust.PubSub
  alias Gust.Repo

  @behaviour Gust.PGNotifier
  @channel "run_dispatch"

  @impl true
  def start_link(opts), do: Postgrex.Notifications.start_link(opts)

  @impl true
  def listen(server, channel), do: Postgrex.Notifications.listen(server, channel)

  @impl true
  def notify do
    Repo |> SQL.query!("SELECT pg_notify($1, $2)", [@channel, "work_available"])
    :ok
  end

  @impl true
  def enqueue_all(runs) do
    {:ok, runs} =
      Repo.transaction(fn ->
        runs = Flows.update_runs_status(runs, :enqueued)
        notify()

        runs
      end)

    Enum.each(runs, &PubSub.broadcast_run_status(&1.id, :enqueued))
    runs
  end
end
