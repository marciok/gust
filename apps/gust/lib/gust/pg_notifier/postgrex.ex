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
  def enqueue(run) do
    {:ok, run} =
      Repo.transaction(fn ->
        {:ok, run} = Flows.update_run_status(run, :enqueued)
        Repo |> SQL.query!("SELECT pg_notify($1, $2)", [@channel, to_string(run.id)])

        run
      end)

    PubSub.broadcast_run_status(run.id, :enqueued)
    run
  end
end
