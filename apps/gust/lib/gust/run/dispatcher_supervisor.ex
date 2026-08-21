defmodule Gust.Run.DispatcherSupervisor do
  @moduledoc false

  alias Gust.Run.Claimer
  alias Gust.Run.Dispatcher

  use Supervisor

  # coveralls-ignore-start
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # coveralls-ignore-stop

  @impl true
  def init(_opts) do
    children = [Dispatcher.impl(), Claimer]
    Supervisor.init(children, strategy: :rest_for_one)
  end
end
