defmodule Gust.DAG.Runtime.Adapter do
  @moduledoc false

  @callback setup(Gust.DAG.Definition.t()) :: Gust.DAG.Definition.t()
  @callback teardown(Gust.DAG.Definition.t()) :: :ok
end
