defmodule Gust.DAG.TaskDelayer do
  @moduledoc false
  @callback calc_delay(attempt :: integer()) :: integer()

  def calc_delay(attempt), do: impl().calc_delay(attempt)
  def impl, do: Application.get_env(:gust, :dag_task_delayer, Gust.DAG.TaskDelayer.Calculator)
end
