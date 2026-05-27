defmodule Gust.CLI do
  @moduledoc """
  Command-line entrypoint for operational Gust tasks.

  This module is invoked by the release wrapper script and dispatches supported
  CLI commands into the application runtime.

  ## Supported commands

  * `trigger_run <dag_name>`: starts the application, looks up the DAG by name,
    creates a run for it, and dispatches that run through the configured
    `Gust.DAG.Run.Trigger` implementation.
  * `dag_definition <dag_name>`: returns the DAG definition payload as JSON,
    including the definition load status.

  Example:

      gust-cli trigger_run my_dag
  """

  alias Gust.DAG.Definition
  alias Gust.DAG.Loader
  alias Gust.DAG.Run.Trigger
  alias Gust.Flows
  require Logger

  @doc """
  Executes a supported CLI command.

  Currently supported commands:

  * `["trigger_run", dag_name]`
  * `["dag_definition", dag_name]`
  """
  def exec(["trigger_run", dag_name]) do
    load_app()

    dag = Flows.get_dag_by_name(dag_name)
    {:ok, run} = Flows.create_run(%{dag_id: dag.id})
    run = Trigger.dispatch_run(run)

    Logger.warning("Triggered DAG #{dag.name}; Run: #{run.id}")
  end

  def exec(["dag_definition", dag_name]) do
    load_app()

    dag = Flows.get_dag_by_name(dag_name)

    if dag do
      get_dag_def(dag.id)
    else
      raise "There are no DAGs with name: #{dag_name}"
    end
  end

  defp get_dag_def(dag_id) do
    case Loader.get_definition(dag_id) do
      {:ok, dag_def} ->
        %{
          status: :ok,
          definition: Definition.to_map(dag_def)
        }

      {:error, error} ->
        %{
          status: :error,
          error: inspect(error)
        }
    end
    |> Jason.encode!()
  end

  defp load_app do
    Application.ensure_all_started(:gust)
  end
end
