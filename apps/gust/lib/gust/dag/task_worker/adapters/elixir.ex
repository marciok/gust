defmodule Gust.DAG.TaskWorker.Adapters.Elixir do
  @moduledoc false

  use Gust.DAG.TaskWorker
  alias Gust.DAG.Logger

  @impl true
  def handle_info(
        :run,
        %{task: task, dag_def: dag_def, stage_pid: stage_pid, opts: opts} = state
      ) do
    fun_name = String.to_atom(task.name)
    args = [%{run_id: task.run_id}]

    Logger.set_task(task.id, task.attempt)

    {status, result} =
      case try_run(dag_def.mod, fun_name, args, opts[:store_result]) do
        {:ok, result} ->
          {:ok, result}

        {:error, error} ->
          {:error, error}
      end

    Logger.unset()

    send(stage_pid, {:task_result, result, task.id, status})

    {:stop, :normal, state}
  end

  defp try_run(mod, fun_name, args, store_result) do
    apply_and_validate(mod, fun_name, args, store_result)
  rescue
    e -> {:error, e}
  end

  defp apply_and_validate(mod, fun_name, args, store_result) do
    result = apply(mod, fun_name, args)
    maybe_validate_result(store_result, result)
  end

  def maybe_validate_result(false, result), do: {:ok, result}
  def maybe_validate_result(true, result) when is_map(result), do: {:ok, result}

  def maybe_validate_result(true, result) do
    raise("Task returned #{inspect(result)} but store_result requires a map")
  end
end
