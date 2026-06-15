defmodule Gust.DAG.Runner.DAGWorker do
  @moduledoc false
  use GenServer

  alias Gust.DAG.{Adapter, Definition, StageRunnerSupervisor, TaskExpander}
  alias Gust.DAG.StageCoordinator, as: Coord
  alias Gust.Flows
  alias Gust.PubSub
  alias Gust.Run.Claim

  alias __MODULE__, as: State

  defstruct run: nil,
            dag_def: %Definition{},
            stages: [],
            reclaim_token: nil,
            reclaim_run_delay: nil,
            runtime_id: nil

  @status_map %{
    ok: :succeeded,
    upstream_failed: :failed,
    skipped: :succeeded,
    error: :failed,
    non_recoverable_error: :failed,
    cancelled: :failed
  }

  @impl true
  def init(%State{dag_def: dag_def, run: run} = state) do
    runtime_id = random_udid()

    dag_def =
      dag_def
      |> runtime_adapter()
      |> then(& &1.setup(dag_def, runtime_id))

    delay = Application.get_env(:gust, :reclaim_run_delay, 5_000)

    token = run.claim_token

    state = %{
      state
      | dag_def: dag_def,
        reclaim_token: token,
        reclaim_run_delay: delay,
        runtime_id: runtime_id
    }

    Process.send_after(self(), {:renew_claim, token}, delay)
    {:ok, state, {:continue, :init_stage}}
  end

  def child_spec(args) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [args]},
      restart: :temporary,
      type: :worker
    }
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, struct!(State, args),
      name: via_tuple("dag_run_#{args[:run].id}")
    )
  end

  defp via_tuple(name) do
    {:via, Registry, {Gust.Registry, name}}
  end

  defp expand_task(task, run_id, params_list) do
    params_list
    |> TaskExpander.expand_over(task, run_id, fn task_name, index ->
      {:ok, task} = reconcile_mapped_task(task_name, run_id, index)
      task
    end)
    |> Enum.map(fn {status, {task, _params}} -> {status, task} end)
  end

  @impl true
  def handle_continue(
        :init_stage,
        %State{run: run, dag_def: %Definition{stages: [stage | next_stages]} = dag_def} = state
      ) do
    dag_id = run.dag_id
    id = run.id
    PubSub.broadcast_run_started(dag_id, id)
    start_stage(stage, run.id, dag_def)
    update_status(run, :running)
    state = Map.put(state, :stages, next_stages)

    {:noreply, state}
  end

  defp start_stage(stage, run_id, dag_def) do
    {:ok, tasks} = Flows.reconcile_run_tasks(stage, run_id)

    stage =
      for {:ok, task} <- tasks do
        status = Coord.process_task(task, dag_def.tasks)

        case status do
          {:expand_task, []} ->
            {:skipped, task}

          {:expand_task, params_list} ->
            expand_task(task, run_id, params_list)

          {:expand_task_error, error} ->
            {{:non_recoverable_error, error}, task}

          {:already_expanded, params} ->
            {:ok, task} = Flows.update_task_mapping(task, task.map_index, params)
            {:ok, task}

          status ->
            {status, task}
        end
      end
      |> List.flatten()

    {:ok, _pid} = StageRunnerSupervisor.start_child(dag_def, stage, run_id)
  end

  @impl true
  def handle_info(
        {:stage_completed, status},
        %State{stages: [], dag_def: dag_def, run: run, runtime_id: runtime_id} = state
      ) do
    update_status(run, @status_map[status])
    options = dag_def.options

    {callback_fn_name, _options} = Keyword.pop(options, :on_finished_callback)

    if callback_fn_name do
      dag_def
      |> runtime_adapter()
      |> then(& &1.on_finished_callback(dag_def, callback_fn_name, run, status))
    end

    dag_def
    |> runtime_adapter()
    |> then(& &1.teardown(dag_def, runtime_id))

    {:stop, :normal, state}
  end

  def handle_info(
        {:renew_claim, token},
        %State{
          run: run,
          reclaim_run_delay: delay
        } = state
      ) do
    run = Claim.renew_run(run.id, token)

    if run do
      Process.send_after(self(), {:renew_claim, token}, delay)
      {:noreply, %{state | run: run}}
    else
      {:stop, :normal, state}
    end
  end

  def handle_info(
        {:stage_completed, _status},
        %State{stages: [stage | next_stages], dag_def: dag_def, run: run} = state
      ) do
    start_stage(stage, run.id, dag_def)

    {:noreply, %{state | stages: next_stages}}
  end

  defp update_status(run, status) do
    Flows.update_run_status(run, status) |> broadcast()
  end

  defp broadcast({:ok, %Flows.Run{id: id, status: status}}) do
    Gust.PubSub.broadcast_run_status(id, status)
  end

  defp runtime_adapter(%Definition{adapter: adapter}) do
    Adapter.impl!(adapter, :runtime)
  end

  defp random_udid do
    timestamp = :os.system_time(:microsecond)
    random = :crypto.strong_rand_bytes(4) |> Base.encode16()
    "#{timestamp}-#{random}"
  end

  defp reconcile_mapped_task(name, run_id, map_index) do
    case Flows.get_task_by_name(name, run_id, map_index) do
      nil ->
        Flows.create_task(%{run_id: run_id, name: name, map_index: map_index})

      %Flows.Task{status: :running} = task ->
        Flows.update_task_status(task, :created)

      %Flows.Task{} = task ->
        {:ok, task}
    end
  end
end
