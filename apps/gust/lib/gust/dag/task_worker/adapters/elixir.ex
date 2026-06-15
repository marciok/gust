defmodule Gust.DAG.TaskWorker.Adapters.Elixir do
  @moduledoc false

  use Gust.DAG.TaskWorker
  alias Gust.DAG.Logger

  defp try_skip_cond(nil, _mod, _args), do: false

  defp try_skip_cond(skip_fn, mod, args) do
    case apply(mod, skip_fn, args) do
      skip when is_boolean(skip) ->
        skip

      invalid_skip ->
        raise(":skip_if returned #{inspect(invalid_skip)} but requires a boolean")
    end
  rescue
    e -> {:error, e}
  end

  @impl true
  def handle_info(
        :run,
        %{task: task, dag_def: dag_def, stage_pid: stage_pid, opts: opts} = state
      ) do
    fn_name = String.to_existing_atom(task.name)
    args = [task_context(task)]

    Logger.set_task(task.id, task.attempt)

    {status, result} =
      case try_skip_cond(opts[:skip_if], dag_def.mod, args) do
        false ->
          try_run(dag_def.mod, fn_name, args, opts[:store_result])

        true ->
          {:skipped, %{}}

        {:error, error} ->
          {:error, error}
      end

    Logger.unset()

    send(stage_pid, {:task_result, result, task.id, status})

    {:stop, :normal, state}
  end

  defp try_run(mod, fn_name, args, store_result) do
    apply_and_validate(mod, fn_name, args, store_result)
  rescue
    e -> {:error, e}
  end

  defp apply_and_validate(mod, fn_name, args, store_result) do
    result = apply(mod, fn_name, args)
    maybe_validate_result(store_result, result)
  end

  def maybe_validate_result(false, result), do: {:ok, result}
  def maybe_validate_result(true, result) when is_map(result), do: {:ok, result}

  def maybe_validate_result(true, result) when is_list(result),
    do: {:ok, %{gust_task_items: result}}

  def maybe_validate_result(true, result) do
    raise("Task returned #{inspect(result)} but store_result requires a map")
  end

  defp task_context(%{map_index: nil} = task), do: %{run_id: task.run_id}

  defp task_context(task),
    do: %{run_id: task.run_id, params: task.params}
end
