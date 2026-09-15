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
