defmodule Gust.Run.Pooler do
  @moduledoc false

  use GenServer

  alias Gust.Flows
  alias Gust.PubSub

  @behaviour Gust.Run.Dispatcher

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl Gust.Run.Dispatcher
  def enqueue_all(runs) do
    runs = Flows.update_runs_status(runs, :enqueued)

    Enum.each(runs, &PubSub.broadcast_run_status(&1.id, :enqueued))
    PubSub.broadcast_run_dispatch_wake()
    runs
  end

  @impl Gust.Run.Dispatcher
  def setup do
    GenServer.call(__MODULE__, {:setup, self()})
  end

  @impl true
  def init(opts) do
    PubSub.subscribe_run_dispatch()
    schedule_poll()
    {:ok, %{claimer: nil, opts: opts}}
  end

  @impl true
  def handle_call({:setup, claimer}, _from, state) do
    {:reply, :ok, %{state | claimer: claimer}}
  end

  @impl true
  def handle_info(:poll_runs, state) do
    message_claimer(state)
    schedule_poll()
    {:noreply, state}
  end

  def handle_info({:run_dispatch, :wake}, state) do
    message_claimer(state)
    {:noreply, state}
  end

  defp message_claimer(%{claimer: nil}), do: :ok
  defp message_claimer(%{claimer: claimer}), do: send(claimer, :claim_runs)

  defp schedule_poll do
    tick = Application.get_env(:gust, :claim_runs_tick, 2_000)
    Process.send_after(self(), :poll_runs, tick)
  end
end
