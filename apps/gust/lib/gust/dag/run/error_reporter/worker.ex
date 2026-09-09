defmodule Gust.DAG.Run.ErrorReporter.Worker do
  @moduledoc false

  use GenServer

  require Logger

  alias Gust.DAG.Run.ErrorReporter
  alias Gust.DAG.Run.ErrorReporter.ExternalReference
  alias Gust.{Flows, PubSub}

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
    case call_reporter(reporter, exception, stacktrace, data) do
      {:ok, :ok} ->
        :ok

      {:ok, {:ok, reference}} ->
        attach_reference(data, reference)
    end
  end

  defp call_reporter(reporter, exception, stacktrace, data) do
    {:ok, reporter.capture(exception, stacktrace, data)}
  rescue
    error ->
      log_failure(reporter, :error, error, __STACKTRACE__)
      :error
  catch
    kind, reason ->
      log_failure(reporter, kind, reason, __STACKTRACE__)
      :error
  end

  defp attach_reference(data, reference) do
    if ExternalReference.valid?(reference) do
      case Flows.attach_task_error_reference(data.task_id, reference) do
        {:ok, task} ->
          PubSub.broadcast_task_updated(task.id)

        {:error, :stale_task} ->
          stale_reference(data.task_id)
      end
    else
      invalid_reference(reference)
    end
  end

  defp stale_reference(task_id),
    do:
      Logger.debug(
        "Ignored an external error reference for task #{task_id} because it is no longer failed"
      )

  defp invalid_reference(reference),
    do:
      Logger.error("Error reporter returned an invalid external reference: #{inspect(reference)}")

  defp log_failure(reporter, kind, reason, stacktrace) do
    Logger.error(
      "Error reporter #{inspect(reporter)} failed:\n#{Exception.format(kind, reason, stacktrace)}"
    )
  end
end
