defmodule Gust.DAG.Terminator do
  @moduledoc false
  @callback kill_task(task :: Gust.Flows.Task.t(), status :: atom()) :: any()
  @callback cancel_timer(task :: Gust.Flows.Task.t(), status :: atom()) :: any()

  # coveralls-ignore-start
  def kill_task(task, status), do: impl().kill_task(task, status)
  def cancel_timer(task, status), do: impl().cancel_timer(task, status)
  def impl, do: Application.get_env(:gust, :dag_terminator, Gust.DAG.Terminator.Process)
  # coveralls-ignore-stop
end
