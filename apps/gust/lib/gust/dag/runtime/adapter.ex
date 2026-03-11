defmodule Gust.DAG.Runtime.Adapter do
  @moduledoc false

  @type runtime_id :: String.t()
  @type callback_name :: atom()

  @callback setup(Gust.DAG.Definition.t(), runtime_id()) :: Gust.DAG.Definition.t()
  @callback teardown(Gust.DAG.Definition.t(), runtime_id()) :: :ok
  @callback on_finished_callback(Gust.DAG.Definition.t(), callback_name(), term(), term()) :: :ok
  @callback kill(term()) :: :ok
end
