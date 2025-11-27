defmodule Gust.DAG.Compiler do
  @moduledoc false
  @type dag_def :: Gust.DAG.Definition.t()

  @callback compile(dag_def) :: module()
  @callback purge(module()) :: nil

  def compile(dag_def), do: impl().compile(dag_def)
  def purge(mod), do: impl().purge(mod)

  defp impl, do: Application.get_env(:gust, :dag_compiler, Gust.DAG.Compiler.Code)
end
