defmodule ChildResumesParent do
  use Gust.DSL, on_finished_callback: :resume_parent

  require Logger

  alias Gust.DAG.TaskWaiter
  alias Gust.Flows

  task :build_result, save: true, ctx: %{run_id: run_id} do
    run = Flows.get_run!(run_id)
    message = Map.get(run.params, "message", "hello from child")

    result = %{
      "message" => String.upcase(message),
      "child_run_id" => run_id
    }

    Logger.info("Child built result: #{inspect(result)}")

    %{result: result}
  end

  def resume_parent(status, run) do
    wait_key = Map.fetch!(run.params, "wait_key")
    parent_run_id = Map.fetch!(run.params, "parent_run_id")
    result_task = Flows.get_task_by_name_run("build_result", run.id)

    payload = %{
      "child_run_id" => run.id,
      "child_status" => to_string(status),
      "child_result" => result_task && result_task.result["result"]
    }

    {:ok, _tasks} = TaskWaiter.resume(wait_key, run_id: parent_run_id, payload: payload)
  end
end
