defmodule Gust.DAG.RunRestarter.Worker do
  @moduledoc false
  alias Gust.DAG.{Graph, Loader, RunnerSupervisor, Definition}
  alias Gust.Flows
  @behaviour Gust.DAG.RunRestarter
  use GenServer

  @impl true
  def init(init_arg) do
    {:ok, init_arg}
  end

  def child_spec(arg) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [arg]},
      type: :worker
    }
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def start_dag(dag_id) do
    GenServer.call(__MODULE__, {:start_dag, dag_id})
  end

  @impl true
  def restart_run(run) do
    GenServer.call(__MODULE__, {:restart_run, run})
  end

  @impl true
  def restart_task(graph, task) do
    GenServer.call(__MODULE__, {:restart_task, graph, task})
  end

  @impl true
  def restart_dags(dags) do
    GenServer.call(__MODULE__, {:restart_dags, dags})
  end

  @impl true
  def restart_enqueued(dag_id) do
    GenServer.cast(__MODULE__, {:restart_enqueued, dag_id})
  end

  @impl true
  def handle_cast({:restart_enqueued, dag_id}, state) do
    with {:ok, dag_def} <- Loader.get_definition(dag_id), false <- Definition.errors?(dag_def) do
      get_runs([dag_id], [:enqueued]) |> Enum.each(&start_run(&1, {:ok, dag_def}))
    end

    {:noreply, state}
  end

  @impl true
  def handle_call({:start_dag, dag_id}, _from, state) do
    {:ok, run} = Flows.create_run(%{dag_id: dag_id})

    run =
      if Flows.get_dag!(dag_id).enabled do
        with {:ok, dag_def} <- Loader.get_definition(run.dag_id),
             false <- Definition.errors?(dag_def) do
          {:ok, _pid} = RunnerSupervisor.start_child(run, dag_def)
          run
        else
          true -> nil
        end
      else
        {:ok, run} = Flows.update_run_status(run, :enqueued)
        run
      end

    {:reply, run, state}
  end

  @impl true
  def handle_call({:restart_run, run}, _from, state) do
    Flows.get_run_with_tasks!(run.id)
    |> then(fn run -> run.tasks end)
    |> Enum.each(fn task ->
      {:ok, _task} = Flows.update_task_status(task, :created)
    end)

    {:ok, run} = Flows.update_run_status(run, :running)

    {:ok, dag_def} = Loader.get_definition(run.dag_id)
    {:ok, _pid} = RunnerSupervisor.start_child(run, dag_def)

    {:reply, run, state}
  end

  @impl true
  def handle_call({:restart_task, graph, task}, _from, state) do
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
    {:ok, run} = Flows.update_run_status(run, :running)

    {:ok, dag_def} = Loader.get_definition(run.dag_id)
    {:ok, _pid} = RunnerSupervisor.start_child(run, dag_def)

    {:reply, tasks_to_clear, state}
  end

  @impl true
  def handle_call({:restart_dags, dags}, _from, state) do
    dag_ids = Map.keys(dags)

    runs =
      get_runs(dag_ids, [:running, :retrying])
      |> Stream.filter(fn run ->
        case dags[run.dag_id] do
          {:ok, dag_def} ->
            Definition.errors?(dag_def) == false

          {:error, _err} ->
            false
        end
      end)
      |> Stream.map(fn run -> start_run(run, dags[run.dag_id]) end)
      |> Enum.to_list()

    {:reply, runs, state}
  end

  defp get_runs(dag_ids, statuses) do
    Flows.get_running_runs_by_dag(dag_ids, statuses)
  end

  defp start_run(run, {:ok, dag_def}) do
    {:ok, _pid} = RunnerSupervisor.start_child(run, dag_def)
    run
  end
end
