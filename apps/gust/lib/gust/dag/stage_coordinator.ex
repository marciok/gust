defmodule Gust.DAG.StageCoordinator do
  @moduledoc false
  @type stage_spec :: map()
  @type task_id :: integer()
  @type run_id :: integer()
  @type task :: Gust.Flows.Task.t()
  @type ref :: reference()
  @type reason :: term()

  @callback new(list(task_id)) :: stage_spec
  @callback put_running(stage_spec, task_id) :: stage_spec
  @callback apply_task_result(stage_spec, task, atom()) ::
              {:continue, stage_spec} | {:finished, stage_spec} | {:reschedule, stage_spec, task, integer()}
  @callback update_restart_timer(stage_spec, task, ref) :: stage_spec
  @callback process_task(task, map()) ::
              :ok | :upstream_failed | :already_processed

  def put_running(stage_spec, task_id), do: impl().put_running(stage_spec, task_id)

  def new(pending_task_ids),
    do: impl().new(pending_task_ids)

  def process_task(task, tasks),
    do: impl().process_task(task, tasks)

  def apply_task_result(stage_spec, ref, reason),
    do: impl().apply_task_result(stage_spec, ref, reason)

  def update_restart_timer(coord, task, ref),
    do: impl().update_restart_timer(coord, task, ref)

  def impl,
    do:
      Application.get_env(:gust, :dag_stage_coordinator, Gust.DAG.StageCoordinator.RetryingRunner)
end
