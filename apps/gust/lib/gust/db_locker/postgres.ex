defmodule Gust.DBLocker.Postgres do
  @moduledoc """
  Implements DB-backed advisory locking using Postgres.

  `pg_try_advisory_lock/1` is a session-level lock: it belongs to the database
  session that took it. Behind a connection pooler in transaction mode (e.g.
  PgBouncer on Fly.io Managed Postgres) a `Gust.Repo` connection is not pinned to
  a session, so the lock could be re-acquired by another node or outlive its
  owner. The lock is therefore taken over a dedicated connection that reuses
  `Gust.Repo`'s settings, merged with `config :gust, :db_locker_connection`:

      config :gust, :db_locker_connection, url: System.get_env("DIRECT_DATABASE_URL")

  The success flag is passed to the provided callback. While it runs, the
  calling process is linked to the connection pool, which stops if the
  connection drops, since the lock is released along with its session.
  The connection is closed once the callback returns or raises.
  """

  @behaviour Gust.DBLocker

  def try_lock(lock_key, attempt_result_fun) do
    {:ok, conn} = Postgrex.start_link(connection_opts())

    try do
      %{rows: [[success]]} = Postgrex.query!(conn, "SELECT pg_try_advisory_lock($1)", [lock_key])
      attempt_result_fun.(success)
    after
      GenServer.stop(conn)
    end
  end

  defp connection_opts do
    :gust
    |> Application.get_env(:db_locker_connection, [])
    |> Gust.Repo.connection_opts()
    |> Keyword.merge(pool_size: 1, backoff_type: :stop, max_restarts: 0)
  end
end
