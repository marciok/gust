defmodule Gust.DAG.Runner.DAGWorker do
  @moduledoc false
  use GenServer

  alias Gust.DAG.{Compiler, Definition, StageRunnerSupervisor}
  alias Gust.Flows
  alias Gust.Run.Claim
  alias Gust.PubSub

  alias __MODULE__, as: State

  defstruct run: nil,
            dag_def: %Definition{},
            stages: [],
            reclaim_token: nil,
            reclaim_run_delay: nil

  @status_map %{
    ok: :succeeded,
    upstream_failed: :failed,
    error: :failed,
    cancelled: :failed
  }

  @impl true
  def init(%State{dag_def: dag_def, run: run} = state) do
    runtime_mod = Compiler.compile(dag_def)
    dag_def = %{dag_def | mod: runtime_mod}
    delay = Application.get_env(:gust, :reclaim_run_delay, 5_000)

    token = run.claim_token
    state = %{state | dag_def: dag_def, reclaim_token: token, reclaim_run_delay: delay}

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
    task_ids =
      for name <- stage do
        {:ok, task} = ensure_task(name, run_id)
        task.id
      end

    {:ok, _stage_pid} =
      StageRunnerSupervisor.start_child(dag_def, task_ids, run_id)
  end

  defp ensure_task(name, run_id) do
    case Flows.get_task_by_name_run(name, run_id) do
      nil ->
        Flows.create_task(%{run_id: run_id, name: name})

      %Flows.Task{status: :running} = task ->
        Flows.update_task_status(task, :created)

      %Flows.Task{} = task ->
        {:ok, task}
    end
  end

  @impl true
  def handle_info(
        {:stage_completed, status},
        %State{stages: [], dag_def: dag_def, run: run} = state
      ) do
    update_status(run, @status_map[status])
    options = dag_def.options

    {callback, _options} = Keyword.pop(options, :on_finished_callback)
    if callback, do: apply(dag_def.mod, callback, [status, run])

    Compiler.purge(dag_def.mod)
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
end
