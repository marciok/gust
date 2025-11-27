defmodule Gust.DAG.Loader do
  @moduledoc false

  @callback get_definitions() :: %{term() => Gust.DAG.Definition.t()}
  @callback get_definition(term()) :: Gust.DAG.Definition.t()

  # coveralls-ignore-start
  def get_definitions, do: impl().get_definitions()
  def get_definition(dag_id), do: impl().get_definition(dag_id)
  defp impl, do: Application.get_env(:gust, :dag_loader)
  # coveralls-ignore-stop
end
