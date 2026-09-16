defmodule Gust.Action do
  @moduledoc """
  Behaviour implemented by reusable actions invoked by `Gust.DSL.task_action/3`.
  """

  @callback execute(args :: keyword(), context :: map()) :: term()
end
