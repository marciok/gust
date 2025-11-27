defmodule Gust.DAG.TaskDelayer.Calculator do
  @moduledoc false
  @behaviour Gust.DAG.TaskDelayer

  def calc_delay(attempt) do
    delay = 5_000
    exp_backoff(delay, attempt)
  end

  defp exp_backoff(delay, attempt) do
    (delay * :math.pow(2, attempt - 1)) |> round()
  end
end
