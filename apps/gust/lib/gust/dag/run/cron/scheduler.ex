defmodule Gust.DAG.Run.Cron.Scheduler do
  @moduledoc false
  use Quantum, otp_app: :gust

  require Logger

  alias Gust.Run.Pruner
  alias Quantum.Job

  @impl true
  def init(config) do
    case Pruner.schedule() do
      {:ok, schedule} ->
        Keyword.update(config, :jobs, [prune_job(config, schedule)], fn jobs ->
          [prune_job(config, schedule) | jobs]
        end)

      :disabled ->
        config

      {:error, reason} ->
        Logger.error("Run pruning is off, invalid :run_pruner schedule: #{reason}")
        config
    end
  end

  defp prune_job(config, schedule) do
    [overlap: false]
    |> __new_job__(config)
    |> Job.set_name(Pruner)
    |> Job.set_schedule(schedule)
    |> Job.set_task({Pruner, :prune_all, []})
  end
end
