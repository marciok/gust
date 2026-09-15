# Error Tracking

Gust can asynchronously report terminal task failures without interrupting
DAG execution. Implement the `Gust.DAG.Run.ErrorReporter` behaviour and
configure it as the `:reporter`.

`capture/3` runs asynchronously in `Gust.DAG.Run.ErrorReporter.Worker`.
Exceptions, exits, and throws from an adapter are logged and contained so
they cannot interrupt DAG execution. When it returns an external reference,
the worker adds that reference to the task's persisted error map.

## Sentry example

With the `:sentry` package installed and configured, an adapter can report
task errors through `Sentry.capture_exception/2`:

```elixir
defmodule MyApp.SentryErrorReporter do
  @behaviour Gust.DAG.Run.ErrorReporter

  @impl true
  def capture(exception, stacktrace, metadata) do
    Sentry.capture_exception(exception, stacktrace: stacktrace, tags: metadata)
    :ok
  end
end
```

```elixir
config :gust,
  error_tracking: [reporter: MyApp.SentryErrorReporter]
```

## Custom reporter example

Implement `capture/3` in an adapter module and configure it under the
`:error_tracking` application environment:

```elixir
defmodule MyApp.ErrorReporter do
  @behaviour Gust.DAG.Run.ErrorReporter

  @impl true
  def capture(exception, stacktrace, metadata) do
    response =
      Req.post!("https://errors.example.com/events",
        json: %{
          message: Exception.message(exception),
          stacktrace: Exception.format_stacktrace(stacktrace),
          metadata: metadata
        }
      )

    {:ok, response.body["url"]}
  end
end
```

```elixir
config :gust,
  error_tracking: [reporter: MyApp.ErrorReporter]
```

`capture/3` receives the failed task's `exception`, `stacktrace`, and
`metadata` (`task_id`, `task_name`, `run_id`, `dag_name`). It may return
`:ok`, or `{:ok, external_url}` when the provider exposes an HTTP(S) page
for the captured error.

See the [`Gust.DAG.Run.ErrorReporter`](https://hexdocs.pm/gust/Gust.DAG.Run.ErrorReporter.html)
module documentation for the full behaviour reference.
