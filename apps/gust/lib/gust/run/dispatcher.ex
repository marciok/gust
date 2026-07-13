defmodule Gust.Run.Dispatcher do
  @moduledoc """
  Dispatch strategy used to enqueue runs and initialize claim delivery.

  Configure an implementation with `:run_dispatcher`. Implementations own the
  transport-specific enqueue semantics and arrange for `Gust.Run.Claimer` to
  receive `:claim_runs` messages.
  """

  @callback enqueue(term()) :: term()
  @callback setup() :: :ok

  def enqueue(run), do: impl().enqueue(run)
  def setup, do: impl().setup()

  def impl do
    Application.get_env(:gust, :run_dispatcher, Gust.Run.Pooler)
  end
end
