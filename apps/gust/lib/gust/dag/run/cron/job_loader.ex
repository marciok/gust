defmodule Gust.DAG.Run.Cron.JobLoader do
  @moduledoc false

  import Crontab.CronExpression
  alias Gust.DAG.Definition
  alias Gust.DAG.Loader
  alias Gust.DAG.Run.Cron.Scheduler
  alias Gust.DAG.Run.Trigger
  alias Gust.Flows
  alias Gust.PubSub
  alias Quantum.Job, as: QJob

  use GenServer

  def init(args) do
    state = %{
      reload_schedules?:
        Keyword.get(
          args,
          :reload_schedules?,
          Application.get_env(:gust, :reload_dag_cron, false)
        )
    }

    if state.reload_schedules?, do: PubSub.subscribe_all_files("update")

    {:ok, state, {:continue, :load_jobs}}
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def handle_continue(:load_jobs, state) do
    for {dag_id, {:ok, dag_def}} <- Loader.get_definitions(),
        schedule = dag_def.options[:schedule],
        schedule != nil,
        Definition.empty_errors?(dag_def) do
      add_dag_job(dag_def, dag_id)
    end

    {:noreply, state}
  end

  def handle_info(
        {:dag, :file_updated, %{action: "reload", parse_result: {:ok, dag_def}}},
        state
      ) do
    reload_dag_job(dag_def)
    {:noreply, state}
  end

  def handle_info(
        {:dag, :file_updated, %{action: "removed", dag_name: name}},
        state
      ) do
    delete_job(name)
    {:noreply, state}
  end

  def handle_info({:dag, :file_updated, _payload}, state), do: {:noreply, state}

  def add_dag_job(dag_def, dag_id) do
    schedule = dag_def.options[:schedule]

    Scheduler.new_job()
    |> QJob.set_name(String.to_atom(dag_def.name))
    |> QJob.set_schedule(~e[#{schedule}])
    |> QJob.set_task(fn ->
      {:ok, run} = Flows.create_run(%{dag_id: dag_id})
      run = Trigger.dispatch_run(run)
      PubSub.broadcast_run_started(dag_id, run.id)
      run
    end)
    |> Scheduler.add_job()
  end

  defp reload_dag_job(%Definition{name: name} = dag_def) do
    delete_job(name)

    with true <- Definition.empty_errors?(dag_def),
         schedule when not is_nil(schedule) <- dag_def.options[:schedule],
         %{id: dag_id} <- Flows.get_dag_by_name(name) do
      add_dag_job(dag_def, dag_id)
    else
      _no_job -> :ok
    end
  end

  defp delete_job(name) do
    job_name = String.to_existing_atom(name)

    if Scheduler.find_job(job_name) do
      Scheduler.delete_job(job_name)
    end
  end
end
