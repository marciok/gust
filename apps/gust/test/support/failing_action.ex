defmodule Gust.FailingAction do
  @moduledoc false

  @behaviour Gust.Action

  @impl true
  def execute(_args, _context), do: raise("action failed")
end
