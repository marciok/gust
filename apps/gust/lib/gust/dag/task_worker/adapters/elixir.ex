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
          try do
            try_run(dag_def.mod, fn_name, args, opts[:store_result])
          catch
            :exit, reason ->
              {:error, %RuntimeError{message: inspect(reason)}}
          end

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
    mod
    |> apply_and_validate(fn_name, args, store_result)
    |> maybe_linked_exit_error()
  rescue
    e -> {:error, e}
  end

  defp maybe_linked_exit_error(result) do
    receive do
      {:EXIT, _pid, reason} when not normal_exit?(reason) ->
        {:error, exit_error(reason)}
    after
      0 ->
        result
    end
  end

  defp apply_and_validate(mod, fn_name, args, store_result) do
    result = apply(mod, fn_name, args)
    maybe_validate_result(store_result, result)
  end

  def maybe_validate_result(false, result), do: {:ok, result}

  def maybe_validate_result(true, result) when is_map(result),
    do: validate_serializable(result)

  def maybe_validate_result(true, result) when is_list(result),
    do: validate_serializable(%{gust_task_items: result})

  def maybe_validate_result(true, result) do
    raise("Task returned #{inspect(result)} but store_result requires a map")
  end

  defp validate_serializable(result) do
    case Jason.encode(result) do
      {:ok, _json} ->
        {:ok, result}

      {:error, %Jason.EncodeError{message: message}} ->
        raise("Task result is not JSON-serializable: #{message} (#{inspect(result)})")

      {:error, %Protocol.UndefinedError{value: value}} ->
        raise(
          "Task result is not JSON-serializable: #{inspect(value)} has no Jason encoder (#{inspect(result)})"
        )
    end
  end

  defp task_context(task),
    do: %{run_id: task.run_id, params: task.params}
end
