defmodule GustPy.Executor do
  @callback parse_dag(term()) :: {term(), term()}
  @callback start_task_via_port(term(), term(), term()) :: term()

  defp impl, do: Application.get_env(:gust_py, :executor, GustPy.Executor.UV)

  def parse_dag(file_path), do: impl().parse_dag(file_path)

  def start_task_via_port(dag_def, task_name, context),
    do: impl().start_task_via_port(dag_def, task_name, context)
end
