defmodule Gust.Run.Pruner do
  @moduledoc """
  Deletes old finished runs of DAGs that set a run retention.

  A DAG opts in with `runs: [retention: [max_count: n]]`: its `n` most recent
  finished (`:succeeded` or `:failed`) runs are kept and older ones are
  deleted, together with their tasks and logs. Unfinished runs are never
  deleted and don't count toward `n`. DAGs without a retention keep all runs.

  Pruning runs on a schedule only when the app configures one:

      config :gust, :runs, prune_schedule: "@daily"

  The schedule is a crontab expression, including shortcuts such as `@hourly`
  or `@daily`. `Gust.DAG.Run.Cron.Scheduler` registers the job, so it runs on
  the leader only and never overlaps itself. Without `prune_schedule` nothing
  is deleted, unless `prune/3` is called directly (e.g. by the CLI).

  Runs are deleted in batches, each one a single short statement, and every
  batch broadcasts `Gust.PubSub.broadcast_runs_pruned/2` so open dashboards
  drop the deleted runs. The number of runs deleted per DAG is logged.

  Deleting rows doesn't shrink tables on disk: autovacuum makes the space
  reusable, so tables stop growing. Use `VACUUM FULL` or `pg_repack` once to
  reclaim space on instances that are already large.
  """

  require Logger

  alias Crontab.CronExpression
  alias Crontab.CronExpression.Parser
  alias Gust.DAG.Loader
  alias Gust.DAG.Options
  alias Gust.Flows
  alias Gust.PubSub

  @batch_size 200

  @doc """
  Returns the configured `prune_schedule`, parsed.

  Returns `:disabled` when it isn't configured, and an error for an invalid
  expression or `@reboot`, which would only prune when the Scheduler starts.
  """
  @spec schedule() :: {:ok, CronExpression.t()} | :disabled | {:error, String.t()}
  def schedule, do: parse_schedule(configured_schedule())

  @doc """
  Returns the `prune_schedule` as configured, or `nil` when it isn't set.
  """
  @spec configured_schedule() :: term()
  def configured_schedule do
    :gust |> Application.get_env(:runs, []) |> Keyword.get(:prune_schedule)
  end

  defp parse_schedule(nil), do: :disabled

  defp parse_schedule(expression) when is_binary(expression) do
    case Parser.parse(expression) do
      {:ok, %CronExpression{reboot: true}} ->
        {:error, "@reboot is not supported, it would only prune when the leader starts"}

      {:ok, schedule} ->
        {:ok, schedule}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_schedule(expression), do: {:error, "expected a string, got: #{inspect(expression)}"}

  @doc """
  Prunes every loaded DAG that sets a retention.

  Returns a map of DAG name to the number of runs deleted.
  """
  @spec prune_all() :: %{String.t() => non_neg_integer()}
  def prune_all do
    Map.new(retained_dags(), fn dag -> {dag.name, prune(dag.dag_id, dag.max_count)} end)
  end

  @doc """
  Lists the loaded DAGs that set a retention, sorted by name.
  """
  @spec retained_dags() :: [%{dag_id: integer(), name: String.t(), max_count: pos_integer()}]
  def retained_dags do
    for {dag_id, {:ok, dag_def}} <- Loader.get_definitions(),
        max_count = Options.max_count(dag_def),
        max_count != nil do
      %{dag_id: dag_id, name: dag_def.name, max_count: max_count}
    end
    |> Enum.sort_by(& &1.name)
  end

  @doc """
  Deletes the finished runs of a DAG beyond the `max_count` most recent ones
  and returns how many were deleted.

  ## Options

    * `:dry_run` - when `true`, deletes nothing and returns how many runs
      would be deleted. Defaults to `false`.
    * `:batch_size` - runs deleted per statement. Defaults to #{@batch_size}.
  """
  @spec prune(integer(), pos_integer(), keyword()) :: non_neg_integer()
  def prune(dag_id, max_count, opts \\ []) do
    if Keyword.get(opts, :dry_run, false) do
      Flows.count_prunable_runs(dag_id, max_count)
    else
      batch_size = Keyword.get(opts, :batch_size, @batch_size)
      deleted = delete_batches(dag_id, max_count, batch_size, 0)

      if deleted > 0 do
        Logger.info("Pruned #{deleted} runs of DAG #{dag_id}, keeping the last #{max_count}")
      end

      deleted
    end
  end

  defp delete_batches(dag_id, max_count, batch_size, total) do
    case Flows.delete_prunable_runs(dag_id, max_count, batch_size) do
      [] ->
        total

      run_ids ->
        PubSub.broadcast_runs_pruned(dag_id, run_ids)
        delete_batches(dag_id, max_count, batch_size, total + length(run_ids))
    end
  end
end
