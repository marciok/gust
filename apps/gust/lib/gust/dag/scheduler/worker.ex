defmodule Gust.DAG.Scheduler.Worker do
  @moduledoc false
  @behaviour Gust.DAG.Scheduler

  import Crontab.CronExpression
  alias Gust.DAG.Cron
  alias Gust.DAG.Definition
  use GenServer
  alias Quantum.Job, as: QJob

  def init(args) do
    {:ok, args}
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def schedule(dag_defs) do
    GenServer.call(__MODULE__, {:load_dags, dag_defs})
  end

  def handle_call({:load_dags, dag_defs}, _from, state) do
    jobs =
      for {dag_id, {:ok, dag_def}} <- dag_defs,
          schedule = dag_def.options[:schedule],
          schedule != nil,
          Definition.errors?(dag_def) == false do
        add_dag_job(dag_def, dag_id)
      end

    {:reply, jobs, state}
  end

  def add_dag_job(dag_def, dag_id) do
    schedule = dag_def.options[:schedule]

    Cron.new_job()
    |> QJob.set_name(String.to_atom(dag_def.name))
    |> QJob.set_schedule(~e[#{schedule}])
    |> QJob.set_task({Gust.DAG.RunRestarter, :start_dag, [dag_id]})
    |> Cron.add_job()
  end
end
