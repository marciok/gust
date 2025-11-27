defmodule Gust.DAG.Scheduler do
  @moduledoc false

  @callback schedule(%{integer() => {:ok, Gust.DAG.Definition.t()} | {:error, term()}}) :: :ok

  def schedule(dag_defs), do: impl().schedule(dag_defs)

  defp impl, do: Application.get_env(:gust, :dag_scheduler)
end
