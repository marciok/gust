# Configuration

Gust is configured through the `:gust` application environment. This guide
covers the dispatch strategy for picking up ready runs, and how to register
language adapters for parsing and executing DAGs.

## Run Dispatcher

Choose how Gust picks up runs that are ready to execute by setting
`run_dispatcher`:

```elixir
config :gust, run_dispatcher: Gust.Run.Pooler
```

### Pooling

`Gust.Run.Pooler` is the default dispatcher. It periodically polls the
database for ready runs, so no extra database setup is required.

### PG Notify

`Gust.PGNotifier.Worker` listens for PostgreSQL `LISTEN`/`NOTIFY` instead of
polling:

```elixir
config :gust, run_dispatcher: Gust.PGNotifier.Worker
```

The notification connection reuses `Gust.Repo`'s database settings. Optional
connection-specific settings can be supplied separately, for example:

```elixir
config :gust, :pg_notifications, reconnect_backoff: 2_000
```

Gust manages notification reconnection through its supervision tree, so
`:sync_connect` and `:auto_reconnect` overrides are ignored. Enqueuing and
notification happen in the same database transaction, and the claimer checks
the durable run queue once after every successful subscription. The
PostgreSQL dispatcher does not periodically poll the database.

You can find a full example [here](https://github.com/marciok/gust/tree/main/examples/docker).

## Leader Election

Gust elects a single leader node, which runs the cron scheduler, by holding a
PostgreSQL session-level advisory lock. The lock is taken over a dedicated
connection that reuses `Gust.Repo`'s database settings. Overrides, including a
`:url`, can be set with:

```elixir
config :gust, :db_locker_connection, url: System.get_env("DIRECT_DATABASE_URL")
```

If the connection holding the lock drops, the node steps down and tries to
acquire the lock again.

### Connection poolers (PgBouncer, Fly.io Managed Postgres)

Session-level advisory locks and `LISTEN`/`NOTIFY` need a connection that stays
bound to one database session. PgBouncer in transaction mode (which Fly.io
recommends for Ecto) does not provide that: two nodes could both become leader,
or the lock could outlive a node that crashed. In that setup, keep `Gust.Repo` on the pooled
URL and point the lock and notification connections at the direct one:

```elixir
direct_url = System.fetch_env!("DIRECT_DATABASE_URL")

config :gust, :db_locker_connection, url: direct_url
config :gust, :pg_notifications, url: direct_url
```

The bundled `config/runtime.exs` does this when `DIRECT_DATABASE_URL` is set.
It must point to the same database through a direct PostgreSQL endpoint (or a
PgBouncer endpoint configured for session pooling), on every node. Opening a
dedicated Postgrex connection to a transaction-pooled URL does not bypass
PgBouncer or make session locks safe. Gust does not detect the pooler's mode;
without this override it continues to use the repo's connection settings.

## DAG Adapters

Gust parses and runs DAGs through language adapters registered under
`dag_adapter`. Elixir is supported out of the box; other languages, such as
Python via [`gust_py`](https://github.com/marciok/gust_py), register
themselves the same way:

```elixir
config :gust,
  dag_adapter: [
    python: %{
      parser: GustPy.Parser.Adapter,
      runtime: GustPy.Runtime.Adapter,
      task_worker: GustPy.TaskWorker.Adapter
    }
  ]
```

Each adapter provides a `parser`, `runtime`, and `task_worker` module for its
language. See the
[Writing Python DAGs guide](https://hexdocs.pm/gust_py/writing_python_dags.html)
for a full example.
