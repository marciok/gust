defmodule Gust.DAG.Terminator do
  @moduledoc false

  alias Gust.Flows

  @type cancel_result :: {:ok, Flows.Task.t()} | {:error, term()}
  @type stop_run_result :: {:ok, Flows.Run.t()} | {:error, term()}

  @callback cancel(task :: Flows.Task.t()) :: cancel_result()
  @callback stop_run(run :: Flows.Run.t()) :: stop_run_result()

  def cancel(%Flows.Task{} = task), do: impl().cancel(task)
  def stop_run(%Flows.Run{} = run), do: impl().stop_run(run)

  def impl, do: Application.get_env(:gust, :dag_terminator, Gust.DAG.Terminator.Gateway)
end
