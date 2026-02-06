defmodule Gust.DAG.Runtime.Adapter do
  @moduledoc false

  @callback setup(Gust.DAG.Definition.t(), String.t()) :: Gust.DAG.Definition.t()
  @callback teardown(Gust.DAG.Definition.t(), String.t()) :: :ok
end
