defmodule Gust.DAG.Runner.StageWorker do
  @moduledoc false
  use GenServer
  alias Gust.DAG.ErrorParser
  alias Gust.DAG.StageCoordinator, as: Coord
  alias Gust.DAG.TaskRunnerSupervisor
  alias Gust.Flows
  alias Gust.PubSub

  @impl true
  def init(init_arg) do
    coord =
      Coord.new(
        for {_status, task} <- init_arg[:stage] do
          task.id
        end
      )

    args = Map.put(init_arg, :coord, coord)

    {:ok, args, {:continue, :process_task}}
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: via_tuple("stage_run_#{args[:run_id]}"))
  end

  defp via_tuple(name) do
    {:via, Registry, {Gust.Registry, name}}
  end

  def child_spec(args) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [args]},
      restart: :temporary,
      type: :worker
    }
  end

  @impl true
  def handle_continue(
        :process_task,
        %{stage: stage, dag_def: dag_def} = state
      ) do
    Enum.each(stage, fn {status, task} ->
      case status do
        :ok ->
          start_task(task, dag_def)

        status when status in [:already_processed, :skipped, :upstream_failed] ->
          send(self(), {:task_result, nil, task.id, status})

        {:non_recoverable_error, error} ->
          send(self(), {:task_result, error, task.id, :non_recoverable_error})
      end
    end)

    {:noreply, state}
  end

  @impl true
  def handle_info(
        {:cancel_timer, task_id, status},
        %{coord: coord} = state
      ) do
    %{restart_timer: ref} = coord.retrying[task_id]
    Process.cancel_timer(ref)

    send(self(), {:task_result, nil, task_id, status})

    {:noreply, state}
  end

  @impl true
  def handle_info(
        {:task_result, result, task_id, status},
        %{coord: coord, dag_def: dag_def} = state
      ) do
    task = apply_task_result(dag_def, task_id, status, result)

    case Coord.apply_task_result(coord, task, status) do
      {:continue, coord} ->
        update_task_result(task, status)

        {:noreply, %{state | coord: coord}}

      {:reschedule, coord, task, time} ->
        update_status(task, :retrying)
        {:ok, task} = Flows.update_task_attempt(task, task.attempt + 1)
        ref = Process.send_after(self(), {:restart_task, task}, time)
        coord = Coord.update_restart_timer(coord, task, ref)

        {:noreply, %{state | coord: coord}}

      {:finished, coord} ->
        update_task_result(task, status)

        dag_runner_pid = lookup_worker("dag_run_#{task.run_id}")
        send(dag_runner_pid, {:stage_completed, status})
        {:stop, :normal, %{state | coord: coord}}
    end
  end

  def handle_info(
        {:restart_task, task},
        %{stage: _stage, dag_def: dag_def, coord: coord} = state
      ) do
    start_task(task, dag_def)
    coord = Coord.put_running(coord, task.id)

    {:noreply, %{state | coord: coord}}
  end

  defp lookup_worker(key) do
    [{pid, _}] = Registry.lookup(Gust.Registry, key)
    pid
  end

  defp apply_task_result(dag_def, task_id, status, result) do
    task = Flows.get_task!(task_id)

    if status in [:error, :non_recoverable_error] do
      update_error(task, result)
    else
      maybe_update_result(task, dag_def.tasks, status, result)
    end
  end

  defp maybe_update_result(task, tasks, status, result) do
    if update_result?(tasks, task.name, status) do
      reset_result_and_error(task, result)
    else
      {:ok, task} = Flows.update_task_error(task, %{})
      task
    end
  end

  defp reset_result_and_error(task, result) do
    {:ok, updated_task} = Flows.update_task_result_error(task, result, %{})
    updated_task
  end

  defp update_error(task, error) do
    error_data = ErrorParser.parse(error)
    {:ok, updated_task} = Flows.update_task_error(task, error_data)
    updated_task
  end

  defp update_task_result(task, status) do
    case status do
      :ok ->
        update_status(task, :succeeded)

      :error ->
        update_status(task, :failed)

      :non_recoverable_error ->
        update_status(task, :failed)

      :upstream_failed ->
        update_status(task, :upstream_failed)

      :skipped ->
        update_status(task, :skipped)

      :cancelled ->
        update_status(task, :failed)

      :already_processed ->
        nil
    end
  end

  defp update_result?(tasks, name, :ok), do: tasks[name][:store_result]
  defp update_result?(_tasks, _name, _status), do: false

  defp start_task(task, dag_def) do
    task_opts =
      dag_def.tasks
      |> Map.fetch!(task.name)

    {:ok, _pid} = TaskRunnerSupervisor.start_child(task, dag_def, self(), task_opts)
    update_status(task, :running)
  end

  defp update_status(task, status) do
    Flows.update_task_status(task, status) |> broadcast()
  end

  defp broadcast({:ok, %Flows.Task{run_id: id, status: status, name: _name, id: task_id}}) do
    PubSub.broadcast_run_status(id, status, task_id)
  end
end
