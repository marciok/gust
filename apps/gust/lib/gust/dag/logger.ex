defmodule Gust.DAG.Logger do
  @moduledoc false
  @callback set_task(task_id :: integer(), attempt :: integer()) :: nil
  @callback unset() :: nil

  def set_task(task_id, attempt), do: impl().set_task(task_id, attempt)
  def unset, do: impl().unset()

  def impl, do: Application.get_env(:gust, :dag_logger)
end
