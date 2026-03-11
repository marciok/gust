defmodule Gust.DAG.Terminator do
  @moduledoc false
  @callback kill_task(task :: Gust.Flows.Task.t(), status :: atom(), term()) :: any()
  @callback cancel_timer(task :: Gust.Flows.Task.t(), status :: atom()) :: any()

  # coveralls-ignore-start
  def kill_task(task, status, runtime), do: impl().kill_task(task, status, runtime)
  def cancel_timer(task, status), do: impl().cancel_timer(task, status)
  def impl, do: Application.get_env(:gust, :dag_terminator, Gust.DAG.Terminator.Worker)
  # coveralls-ignore-stop
end
