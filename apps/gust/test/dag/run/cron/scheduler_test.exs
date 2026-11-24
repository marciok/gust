defmodule DAG.Run.Cron.SchedulerTest do
  use Gust.DataCase, async: false
  import Crontab.CronExpression
  import ExUnit.CaptureLog

  alias Gust.DAG.Run.Cron.Scheduler
  alias Gust.Run.Pruner
  alias Quantum.Job

  defp prune_job(config) do
    Enum.find(config[:jobs], &(&1.name == Pruner))
  end

  describe "init/1" do
    test "registers the prune job with the configured prune_schedule" do
      replace_env(:runs, prune_schedule: "@daily")

      assert %Job{schedule: schedule, overlap: false, task: {Pruner, :prune_all, []}} =
               Scheduler.config() |> Scheduler.init() |> prune_job()

      assert schedule == ~e[@daily]
    end

    test "registers no prune job without prune_schedule" do
      replace_env(:runs, [])

      assert nil == Scheduler.config() |> Scheduler.init() |> prune_job()
    end

    test "logs an error and registers no prune job for an invalid prune_schedule" do
      for expression <- ["nope", "@reboot"] do
        replace_env(:runs, prune_schedule: expression)

        log =
          capture_log(fn ->
            assert nil == Scheduler.config() |> Scheduler.init() |> prune_job()
          end)

        assert log =~ "Run pruning is off, invalid :runs prune_schedule"
      end
    end

    test "the started scheduler has the prune job" do
      replace_env(:runs, prune_schedule: "@yearly")
      start_link_supervised!(Scheduler)

      assert %Job{name: Pruner} = Scheduler.find_job(Pruner)
    end
  end
end
