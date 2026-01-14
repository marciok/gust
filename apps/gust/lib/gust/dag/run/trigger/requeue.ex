defmodule Gust.DAG.Run.Trigger.Requeue do
  alias Gust.PubSub
  alias Gust.Flows
  alias Gust.DAG.Graph

  @behaviour Gust.DAG.Run.Trigger

  def reset_run(run) do
    Flows.get_run_with_tasks!(run.id)
    |> then(fn run -> run.tasks end)
    |> Enum.each(fn task ->
      {:ok, _task} = Flows.update_task_status(task, :created)
    end)

    update_broadcast(run)
  end

  def reset_task(graph, task) do
    tasks_to_clear =
      graph
      |> Graph.build_branch(:downstream, task.name)
      |> List.flatten()
      |> MapSet.new()
      |> Enum.map(fn t_name ->
        t = Flows.get_task_by_name_run(t_name, task.run_id)

        {:ok, t} = Flows.update_task_status(t, :created)
        t
      end)

    run = Flows.get_run!(task.run_id)

    update_broadcast(run)
    tasks_to_clear
  end

  defp update_broadcast(run) do
    {:ok, run} = Flows.update_run_status(run, :enqueued)
    PubSub.broadcast_run_status(run.id, :enqueued)
    run
  end

  def dispatch_all_runs(dag_id) do
    Flows.get_running_runs_by_dag([dag_id], [:created])
    |> Enum.map(fn run ->
      {:ok, run} = Flows.update_run_status(run, :enqueued)
      run
    end)
  end

  def dispatch_run(run) do
    maybe_dispath_enabled_dag(run, Flows.get_dag!(run.dag_id))
  end

  defp maybe_dispath_enabled_dag(run, %Flows.Dag{enabled: false}), do: run

  defp maybe_dispath_enabled_dag(run, %Flows.Dag{enabled: true}) do
    run = update_broadcast(run)
    PubSub.broadcast_run_dispatch(run.id)
    run
  end
end
