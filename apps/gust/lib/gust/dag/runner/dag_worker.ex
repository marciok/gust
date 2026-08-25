defmodule Gust.DAG.Runner.DAGWorker do
  @moduledoc false
  use GenServer

  alias Gust.DAG.{Adapter, Definition, TaskStatus}
  alias Gust.DAG.Runner.{StageBuilder, TaskExecution}
  alias Gust.DAG.StageCoordinator, as: Coord
  alias Gust.Flows
  alias Gust.PubSub
  alias Gust.Run.Claim

  alias __MODULE__, as: State

  defstruct run: nil,
            dag_def: %Definition{},
            stages: [],
            current_task_ids: MapSet.new(),
            coord: nil,
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
        reclaim_run_delay: delay,
        runtime_id: runtime_id
    }

    Process.send_after(self(), {:renew_claim, token}, delay)
    {:ok, state, {:continue, :init_stage}}
  end

  @impl true
  def handle_continue(
        :init_stage,
        %State{run: run, dag_def: %Definition{stages: [stage | next_stages]}} = state
      ) do
    PubSub.broadcast_run_started(run.dag_id, run.id)
    update_run_status(run, :running)

    {:noreply, transition_to_stage(state, stage, next_stages)}
  end

  @impl true
  def handle_call({:restart_task_group, _task_name}, _from, %State{} = state) do
    {:reply, {:error, :cannot_restart_task_group_on_active_run}, state}
  end

  @impl true
  def handle_call({:restart_mapped_task, task_id}, _from, %State{} = state) do
    with %Flows.Task{} = task <- Flows.get_task(task_id),
         :ok <- validate_mapped_task_restart(state, task),
         {:ok, coord} <- Coord.restart_task(state.coord, task.id),
         {:ok, task} <- Flows.prepare_task_restart(task) do
      case TaskExecution.start(task, state.dag_def, self()) do
        {:ok, restarted_task} ->
          {:reply, {:ok, restarted_task}, %{state | coord: coord}}

        {:error, reason} ->
          TaskExecution.fail_start(task, reason)
          {:reply, {:error, reason}, state}
      end
    else
      nil ->
        {:reply, {:error, :task_not_found}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:cancel_task, task_id}, _from, %State{} = state) do
    with %Flows.Task{} = task <- Flows.get_task(task_id),
         :ok <- validate_cancel(state, task),
         :ok <- cancel_execution(task, state) do
      send(self(), {:task_result, nil, task.id, :cancelled})
      {:reply, {:ok, task}, state}
    else
      nil ->
        {:reply, {:error, :task_not_found}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:stop, _from, %State{} = state) do
    case stop_active_tasks(state) do
      :ok ->
        teardown(state.dag_def, state.runtime_id)
        {:stop, :normal, {:ok, state.run}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_info(
        {:task_result, result, task_id, status},
        %State{coord: coord, dag_def: dag_def} = state
      ) do
    task = TaskExecution.apply_result(dag_def, task_id, status, result)

    case Coord.apply_task_result(coord, task, status) do
      {:continue, coord} ->
        TaskExecution.finish(task, status)
        {:noreply, %{state | coord: coord}}

      {:reschedule, coord, task, time} ->
        TaskExecution.update_status!(task, :retrying)
        {:ok, task} = Flows.update_task_attempt(task, task.attempt + 1)
        ref = Process.send_after(self(), {:retry_task, task.id}, time)
        coord = Coord.update_restart_timer(coord, task, ref)

        {:noreply, %{state | coord: coord}}

      {:finished, coord} ->
        TaskExecution.finish(task, status)
        state = %{state | coord: coord}
        finish_stage(TaskExecution.aggregate_status(state.current_task_ids), state)

      {:waiting, coord} ->
        TaskExecution.finish(task, status)
        pause_run(%{state | coord: coord})
    end
  end

  def handle_info({:retry_task, task_id}, %State{dag_def: dag_def, coord: coord} = state) do
    task = Flows.get_task!(task_id)

    case TaskExecution.start(task, dag_def, self()) do
      {:ok, task} ->
        {:noreply, %{state | coord: Coord.put_running(coord, task.id)}}

      {:error, reason} ->
        send(
          self(),
          {:task_result, TaskExecution.start_error(reason), task.id, :non_recoverable_error}
        )

        {:noreply, %{state | coord: Coord.put_running(coord, task.id)}}
    end
  end

  def handle_info(
        {:renew_claim, token},
        %State{
          run: run,
          reclaim_run_delay: delay,
          dag_def: dag_def,
          runtime_id: runtime_id
        } = state
      ) do
    run = Claim.renew_run(run.id, token)

    if run do
      Process.send_after(self(), {:renew_claim, token}, delay)
      {:noreply, %{state | run: run}}
    else
      teardown(dag_def, runtime_id)
      {:stop, :normal, state}
    end
  end

  @impl true
  def handle_info(:pause_run, state), do: pause_run(state)

  defp start_stage(%State{run: run, dag_def: dag_def} = state, stage_names) do
    stage = StageBuilder.build(stage_names, run.id, dag_def)
    task_ids = StageBuilder.task_ids(stage)

    state = %{
      state
      | current_task_ids: MapSet.new(task_ids),
        coord: Coord.new(task_ids)
    }

    process_stage(stage, state)
  end

  defp process_stage(stage, state) do
    Enum.reduce_while(stage, state, fn entry, state ->
      case process_stage_entry(entry, state) do
        {:continue, state} -> {:cont, state}
        {:waiting, state} -> {:halt, schedule_pause(state)}
      end
    end)
  end

  defp process_stage_entry({:ok, task}, %State{dag_def: dag_def} = state) do
    case TaskExecution.start(task, dag_def, self()) do
      {:ok, _task} ->
        {:continue, state}

      {:error, reason} ->
        send(
          self(),
          {:task_result, TaskExecution.start_error(reason), task.id, :non_recoverable_error}
        )

        {:continue, state}
    end
  end

  defp process_stage_entry({status, task}, state)
       when status in [:already_processed, :skipped, :upstream_failed] do
    send(self(), {:task_result, nil, task.id, status})
    {:continue, state}
  end

  defp process_stage_entry({{:non_recoverable_error, error}, task}, state) do
    send(self(), {:task_result, error, task.id, :non_recoverable_error})
    {:continue, state}
  end

  defp process_stage_entry({{:wait_for, wait_for}, task}, %State{coord: coord} = state) do
    {:ok, task} =
      Flows.update_task_wait_state(task, %{
        waiting_for: to_string(wait_for),
        wait_satisfied_at: nil
      })

    TaskExecution.update_status!(task, :waiting)

    case Coord.put_waiting(coord, task.id) do
      {:continue, coord} -> {:continue, %{state | coord: coord}}
      {:waiting, coord} -> {:waiting, %{state | coord: coord}}
    end
  end

  defp finish_stage(status, %State{stages: []} = state), do: finish_run(status, state)

  defp finish_stage(_status, %State{stages: [stage | next_stages]} = state) do
    {:noreply, transition_to_stage(state, stage, next_stages)}
  end

  defp transition_to_stage(state, stage, next_stages) do
    state
    |> Map.put(:stages, next_stages)
    |> start_stage(stage)
  end

  defp finish_run(status, %State{dag_def: dag_def, run: run, runtime_id: runtime_id} = state) do
    update_run_status(run, Map.fetch!(@status_map, status))
    {callback_fn_name, _options} = Keyword.pop(dag_def.options, :on_finished_callback)

    if callback_fn_name do
      dag_def
      |> runtime_adapter()
      |> then(& &1.on_finished_callback(dag_def, callback_fn_name, run, status))
    end

    teardown(dag_def, runtime_id)
    {:stop, :normal, state}
  end

  defp pause_run(%State{dag_def: dag_def, run: run, runtime_id: runtime_id} = state) do
    update_run_status(run, :waiting)
    teardown(dag_def, runtime_id)
    {:stop, :normal, state}
  end

  defp schedule_pause(state) do
    send(self(), :pause_run)
    state
  end

  defp validate_mapped_task_restart(%State{current_task_ids: task_ids}, task) do
    cond do
      is_nil(task.map_index) -> {:error, :task_not_mapped}
      not MapSet.member?(task_ids, task.id) -> {:error, :task_not_on_current_stage}
      not TaskStatus.restartable?(task.status) -> {:error, :task_not_restartable}
      true -> :ok
    end
  end

  defp validate_cancel(%State{current_task_ids: task_ids}, task) do
    cond do
      not MapSet.member?(task_ids, task.id) -> {:error, :task_not_on_current_stage}
      not TaskStatus.cancellable?(task.status) -> {:error, :task_not_cancellable}
      true -> :ok
    end
  end

  defp cancel_execution(%Flows.Task{status: :running} = task, %State{} = state) do
    TaskExecution.cancel(task, state.dag_def)
  end

  defp cancel_execution(%Flows.Task{status: :retrying} = task, %State{coord: coord}) do
    case coord.retrying[task.id] do
      %{restart_timer: ref} ->
        Process.cancel_timer(ref)
        :ok

      nil ->
        {:error, :retry_timer_not_found}
    end
  end

  defp cancel_execution(%Flows.Task{status: :waiting} = task, %State{}) do
    {:ok, _task} =
      Flows.update_task_wait_state(task, %{waiting_for: nil, wait_satisfied_at: nil})

    :ok
  end

  defp stop_active_tasks(%State{} = state) do
    Enum.reduce_while(state.current_task_ids, :ok, fn task_id, :ok ->
      case Flows.get_task(task_id) do
        %Flows.Task{} = task ->
          case maybe_cancel_execution(task, state) do
            :ok -> {:cont, :ok}
            {:error, reason} -> {:halt, {:error, reason}}
          end

        nil ->
          {:cont, :ok}
      end
    end)
  end

  defp maybe_cancel_execution(%Flows.Task{status: status} = task, state) do
    if TaskStatus.cancellable?(status), do: cancel_execution(task, state), else: :ok
  end

  defp update_run_status(run, status) do
    {:ok, %Flows.Run{id: id, status: run_status} = run} =
      Flows.update_run_status(run, status)

    PubSub.broadcast_run_status(id, run_status)
    {:ok, run}
  end

  defp teardown(dag_def, runtime_id) do
    dag_def
    |> runtime_adapter()
    |> then(& &1.teardown(dag_def, runtime_id))
  end

  defp runtime_adapter(%Definition{adapter: adapter}) do
    Adapter.impl!(adapter, :runtime)
  end

  defp random_udid do
    timestamp = :os.system_time(:microsecond)
    random = :crypto.strong_rand_bytes(4) |> Base.encode16()
    "#{timestamp}-#{random}"
  end

  defp via_tuple(name), do: {:via, Registry, {Gust.Registry, name}}
end
