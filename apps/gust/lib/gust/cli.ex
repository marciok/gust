defmodule Gust.CLI do
  @moduledoc """
  Command-line entrypoint for operational Gust tasks.

  This module is invoked by the release wrapper script and dispatches supported
  CLI commands into the application runtime.

  ## Supported commands

  * `trigger_run <dag_name>`: starts the application, looks up the DAG by name,
    creates a run for it, and dispatches that run through the configured
    `Gust.DAG.Run.Trigger` implementation. Returns the run ID as JSON, e.g.
    `{"status":"ok","run_id":42}`.

    Accepts an optional `--run_params` flag with a JSON string payload:

        gust-cli trigger_run my_dag --run_params '{"name": "foo"}'

  * `dag_definition <dag_name>`: returns the DAG definition payload as JSON,
    including the definition load status.

  * `prune_runs <dag_name> --max-count <n> [--dry-run]`: deletes the DAG's
    finished runs beyond the `n` most recent ones, now. `n` is chosen for this
    call only: the DAG's `runs: [retention: ...]` and the `prune_schedule`
    config don't apply. Unfinished runs are never deleted. `--dry-run` deletes
    nothing and reports how many runs would be deleted, e.g.
    `{"status":"ok","dag_name":"my_dag","max_count":100,"dry_run":true,"pruned":120}`.

  Example:

      gust-cli trigger_run my_dag
  """

  alias Gust.DAG.Definition
  alias Gust.DAG.Loader
  alias Gust.DAG.Run.Trigger
  alias Gust.Flows
  alias Gust.Run.Pruner
  require Logger

  @doc """
  Executes a supported CLI command.

  Currently supported commands:

  * `["trigger_run", dag_name]` — optionally with `--run_params '<json>'`
  * `["dag_definition", dag_name]`
  * `["prune_runs", dag_name, "--max-count", n]` — optionally with `--dry-run`
  """
  def exec(["trigger_run", dag_name]) do
    exec(["trigger_run", dag_name, "--run_params", "{}"])
  end

  def exec(["trigger_run", dag_name, "--run_params", json_string]) do
    load_app()

    run_params = Jason.decode!(json_string)

    dag = Flows.get_dag_by_name(dag_name)
    {:ok, run} = Flows.create_run(%{dag_id: dag.id, params: run_params})
    run = Trigger.dispatch_run(run)

    Logger.warning("Triggered DAG #{dag.name}; Run: #{run.id}")

    Jason.encode!(%{status: :ok, run_id: run.id})
  end

  def exec(["dag_definition", dag_name]) do
    load_app()

    dag = get_dag!(dag_name)
    get_dag_def(dag.id)
  end

  def exec(["prune_runs" | args]) do
    load_app()

    {opts, args} = OptionParser.parse!(args, strict: [max_count: :integer, dry_run: :boolean])
    dry_run = Keyword.get(opts, :dry_run, false)

    case {args, opts[:max_count]} do
      {[dag_name], max_count} when is_integer(max_count) and max_count > 0 ->
        dag = get_dag!(dag_name)
        pruned = Pruner.prune(dag.id, max_count, dry_run: dry_run)

        %{status: :ok, dag_name: dag_name, max_count: max_count, dry_run: dry_run, pruned: pruned}

      _invalid ->
        %{status: :error, error: "usage: prune_runs <dag_name> --max-count <n> [--dry-run]"}
    end
    |> Jason.encode!()
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

  defp get_dag!(name) do
    Flows.get_dag_by_name(name) || raise "There are no DAGs with name: #{name}"
  end
end
