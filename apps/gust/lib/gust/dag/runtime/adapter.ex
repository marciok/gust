defmodule Gust.DAG.Runtime.Adapter do
  @moduledoc false

  @callback setup(Gust.DAG.Definition.t(), String.t()) :: Gust.DAG.Definition.t()
  @callback teardown(Gust.DAG.Definition.t(), String.t()) :: :ok
  @callback on_finished_callback(Gust.DAG.Definition.t(), String.t(), term(), term()) :: :ok
end
