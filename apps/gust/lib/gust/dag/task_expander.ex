defmodule Gust.DAG.TaskExpander do
  @moduledoc false

  @callback expand_over(
              params_list :: list(),
              task :: struct(),
              run_id :: integer(),
              create_fn :: function()
            ) :: list()
  @callback get_params(upstream_task_name :: String.t(), run_id :: integer()) ::
              {:expand_task, list()}
              | {:expand_task_error, Exception.t()}
              | list()

  def expand_over(params_list, task, run_id, create_fn) do
    impl().expand_over(params_list, task, run_id, create_fn)
  end

  def get_params(upstream_task_name, run_id), do: impl().get_params(upstream_task_name, run_id)

  def impl, do: Application.get_env(:gust, :dag_task_expander, Gust.DAG.TaskExpander.MapOver)
end
