defmodule Gust.DAG.Run.ErrorReporter.Worker do
  @moduledoc false

  use GenServer

  require Logger

  alias Gust.DAG.Run.ErrorReporter

  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @spec report(ErrorReporter.exception(), ErrorReporter.stacktrace(), ErrorReporter.metadata()) ::
          :ok
  def report(exception, stacktrace, data) do
    GenServer.cast(__MODULE__, {:report, exception, stacktrace, data})
  end

  @impl true
  def init(config), do: {:ok, %{reporter: Keyword.get(config, :reporter)}}

  @impl true
  def handle_cast({:report, _exception, _stacktrace, _data}, %{reporter: nil} = state) do
    Logger.debug("Task error received but not captured because no error reporter is configured")
    {:noreply, state}
  end

  def handle_cast(
        {:report, exception, stacktrace, data},
        %{reporter: reporter} = state
      ) do
    capture(reporter, exception, stacktrace, data)
    {:noreply, state}
  end

  defp capture(reporter, exception, stacktrace, data) do
    reporter.capture(exception, stacktrace, data)
  rescue
    error -> log_failure(reporter, :error, error, __STACKTRACE__)
  catch
    kind, reason -> log_failure(reporter, kind, reason, __STACKTRACE__)
  end

  defp log_failure(reporter, kind, reason, stacktrace) do
    Logger.error(
      "Error reporter #{inspect(reporter)} failed:\n#{Exception.format(kind, reason, stacktrace)}"
    )
  end
end
