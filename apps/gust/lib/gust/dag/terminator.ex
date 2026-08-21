defmodule Gust.DAG.Terminator do
  @moduledoc false

  alias Gust.Flows

  @type result :: {:ok, Flows.Task.t()} | {:error, term()}

  @callback cancel(task :: Flows.Task.t()) :: result()

  def cancel(%Flows.Task{} = task), do: impl().cancel(task)

  def impl, do: Application.get_env(:gust, :dag_terminator, Gust.DAG.Terminator.Gateway)
end
