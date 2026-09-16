defmodule Gust.TestAction do
  @behaviour Gust.Action

  @impl true
  def execute(args, context),
    do: %{message: Keyword.fetch!(args, :message), run_id: context.run_id}
end
