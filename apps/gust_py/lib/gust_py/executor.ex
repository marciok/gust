defmodule GustPy.Executor do
  @moduledoc false

  @callback start_task(term(), term(), term()) :: term()
  @callback run(term()) :: term()

  defp impl, do: Application.get_env(:gust_py, :executor, GustPy.Executor.UV)

  def run(args_list), do: impl().run(args_list)

  def start_task(dag_def, task_name, context),
    do: impl().start_task(dag_def, task_name, context)
end
