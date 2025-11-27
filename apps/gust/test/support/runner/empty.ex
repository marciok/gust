defmodule Gust.DAG.Runner.Empty do
  @moduledoc false
  use GenServer

  def init(init_arg) do
    {:ok, init_arg}
  end

  def start_link(arg) do
    GenServer.start_link(__MODULE__, arg)
  end
end
