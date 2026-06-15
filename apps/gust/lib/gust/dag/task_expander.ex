defmodule Gust.DAG.TaskExpander do
  @moduledoc false

  @callback expand_over(
              params_list :: list(),
              task :: struct(),
              run_id :: integer(),
              create_fn :: function()
            ) :: list()
  @callback get_params(upstream_task_name :: String.t(), run_id :: integer(), term()) ::
              {:expand_task, list()}
              | {:already_expanded, term()}
              | {:expand_task_error, Exception.t()}

  @callback collapse_each(tasks :: list()) :: term()

  def expand_over(params_list, task, run_id, create_fn) do
    impl().expand_over(params_list, task, run_id, create_fn)
  end

  def get_params(upstream_task_name, run_id, map_index),
    do: impl().get_params(upstream_task_name, run_id, map_index)

  def collapse_each(tasks) do
    impl().collapse_each(tasks)
  end

  def impl, do: Application.get_env(:gust, :dag_task_expander, Gust.DAG.TaskExpander.MapOver)
end
