defmodule Gust.DAG.Terminator.Gateway do
  @moduledoc false

  @behaviour Gust.DAG.Terminator

  alias Gust.DAG.Runner.RunGateway
  alias Gust.DAG.TaskWaiter
  alias Gust.Flows

  @impl true
  def cancel(%Flows.Task{} = task) do
    task = Flows.get_task!(task.id)
    run = Flows.get_run!(task.run_id)

    case RunGateway.call(run, {:cancel_task, task.id}) do
      {:error, :run_not_active} when task.status == :waiting -> TaskWaiter.fail(task)
      result -> result
    end
  end

  @impl true
  def stop_run(%Flows.Run{} = run) do
    case RunGateway.call(run, :stop) do
      {:error, :run_not_active} -> {:ok, run}
      result -> result
    end
  end
end
