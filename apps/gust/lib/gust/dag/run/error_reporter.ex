defmodule Gust.DAG.Run.ErrorReporter do
  @moduledoc """
  Defines the contract for reporting terminal DAG task errors.

  ## Sentry example

  With the `:sentry` package installed and configured, an adapter can report
  task errors through `Sentry.capture_exception/2`:

      defmodule MyApp.SentryErrorReporter do
        @behaviour Gust.DAG.Run.ErrorReporter

        @impl true
        def capture(exception, stacktrace, metadata) do
          Sentry.capture_exception(exception, stacktrace: stacktrace, tags: metadata) 
          :ok
        end
      end

      config :gust,
        error_tracking: [reporter: MyApp.SentryErrorReporter]


  ## Custom Reporter example

  Implement `capture/3` in an adapter module and configure it under the
  `:error_tracking` application environment:

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

      config :gust,
        error_tracking: [reporter: MyApp.ErrorReporter]

  `capture/3` runs asynchronously in `Gust.DAG.Run.ErrorReporter.Worker`.
  Exceptions, exits, and throws from an adapter are logged and contained so
  they cannot interrupt DAG execution. When it returns an external reference,
  the worker adds that reference to the task's persisted error map.
  """

  @typedoc "An exception describing the failed task execution."
  @type exception :: Exception.t()

  @typedoc "The original task exception stacktrace, or an empty list when unavailable."
  @type stacktrace :: Exception.stacktrace()

  @typedoc "Context identifying the task and DAG run that failed."
  @type metadata :: %{
          required(:task_id) => integer(),
          required(:task_name) => String.t(),
          required(:run_id) => integer(),
          required(:dag_name) => String.t()
        }

  @typedoc "An absolute HTTP(S) URL for the error in the external reporting service."
  @type external_reference :: String.t()

  @typedoc "The result of delivering an error to the configured reporter."
  @type capture_result :: :ok | {:ok, external_reference()}

  @typedoc "A module implementing this behaviour."
  @type reporter :: module()

  @typedoc "Worker configuration containing an optional reporter implementation."
  @type config :: [reporter: reporter()]

  @doc """
  Delivers a task exception and its execution context to an error provider.

  Implementations may return `:ok` or `{:ok, external_url}` when the
  provider exposes an HTTP(S) page for the captured error. They may raise,
  exit, or throw when delivery fails; the error reporter worker contains and
  logs those failures.
  """
  @callback capture(exception(), stacktrace(), metadata()) :: capture_result()
end
