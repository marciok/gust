defmodule Gust.DAG.MappedTasks do
  @moduledoc false

  def validate!(config \\ config()) do
    config = Keyword.validate!(config, [:max_parallel])
    max_parallel = config[:max_parallel]

    if is_nil(max_parallel) or (is_integer(max_parallel) and max_parallel > 0) do
      :ok
    else
      raise ArgumentError, ":max_parallel must be a positive integer"
    end
  end

  @spec page_size(non_neg_integer(), keyword()) :: pos_integer() | nil
  def page_size(count, config \\ config()) do
    max_parallel = config[:max_parallel]

    if max_parallel && count > max_parallel, do: max_parallel
  end

  defp config, do: Application.get_env(:gust, :mapped_tasks, [])
end
