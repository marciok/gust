defmodule Gust.DAG.TaskWorker.Adapters.Elixir do
  @moduledoc false

  use Gust.DAG.TaskWorker

  @impl true
  def handle_info(
        :run,
        %{task: task, dag_def: dag_def, stage_pid: stage_pid, opts: opts} = state
      ) do
    fun_name = String.to_atom(task.name)
    args = [%{run_id: task.run_id}]

    Gust.DAG.Logger.set_task(task.id, task.attempt)

    {status, result} =
      case try_run(dag_def.mod, fun_name, args, opts[:store_result]) do
        {:ok, result} ->
          {:ok, result}

        {:error, error} ->
          {:error, error}
      end

    Gust.DAG.Logger.unset()

    send(stage_pid, {:task_result, result, task.id, status})

    {:stop, :normal, state}
  end
end
