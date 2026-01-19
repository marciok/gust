defmodule Gust.DAG.Run.Cron.JobLoader do
  @moduledoc false

  import Crontab.CronExpression
  alias Gust.DAG.Definition
  alias Gust.DAG.Run.Cron.Scheduler
  alias Gust.DAG.Run.Trigger
  alias Gust.PubSub
  alias Quantum.Job, as: QJob

  use GenServer

  def init(args) do
    {:ok, args, {:continue, :load_jobs}}
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def handle_continue(:load_jobs, state) do
    for {dag_id, {:ok, dag_def}} <- Gust.DAG.Loader.get_definitions(),
        schedule = dag_def.options[:schedule],
        schedule != nil,
        Definition.empty_errors?(dag_def) do
      add_dag_job(dag_def, dag_id)
    end

    {:noreply, state}
  end

  def add_dag_job(dag_def, dag_id) do
    schedule = dag_def.options[:schedule]

    Scheduler.new_job()
    |> QJob.set_name(String.to_atom(dag_def.name))
    |> QJob.set_schedule(~e[#{schedule}])
    |> QJob.set_task(fn ->
      {:ok, run} = Gust.Flows.create_run(%{dag_id: dag_id})
      run = Trigger.dispatch_run(run)
      PubSub.broadcast_run_started(dag_id, run.id)
      run
    end)
    |> Scheduler.add_job()
  end
end
