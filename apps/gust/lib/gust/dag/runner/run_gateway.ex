defmodule Gust.DAG.Runner.RunGateway do
  @moduledoc false

  alias Gust.Flows.Run

  @type command :: term()
  @type result :: {:ok, term()} | {:error, term()}

  @callback call(Run.t(), command()) :: result()

  def call(%Run{} = run, command), do: impl().call(run, command)

  def impl,
    do: Application.get_env(:gust, :dag_run_gateway, Gust.DAG.Runner.RunGateway.Default)
end
