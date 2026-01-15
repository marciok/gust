defmodule Gust.Leader do
  use GenServer
  require Logger
  alias Gust.DAG.Run.Cron.{Scheduler, JobLoader}

  @lock_key 16_071988

  @default_children [Scheduler, JobLoader]

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(_args) do
    state = %{leader: false}
    {:ok, state, {:continue, :attempt_lock}}
  end

  def attempt_lock do
    parent = self()
    retry_time = Application.get_env(:gust, :leader_lock_attempt, 3_000)

    Task.start_link(fn ->
      Gust.DBLocker.try_lock(@lock_key, fn result ->
        case result do
          false ->
            send(parent, {:set_leader, false})
            Process.send_after(parent, :attempt_lock, retry_time)

          true ->
            send(parent, {:set_leader, true})
            Process.sleep(:infinity)
        end
      end)
    end)
  end

  def handle_call(:leader?, _from, state) do
    {:reply, state[:leader], state}
  end

  def handle_continue(:attempt_lock, state) do
    attempt_lock()
    {:noreply, state}
  end

  def handle_info({:set_leader, false = leader_status}, state) do
    Logger.warning("Node: #{Node.self()} is a follower")

    for {_, pid, _, _} <- DynamicSupervisor.which_children(Gust.LeaderOnlySupervisor) do
      DynamicSupervisor.terminate_child(Gust.LeaderOnlySupervisor, pid)
    end

    {:noreply, %{state | leader: leader_status}}
  end

  def handle_info({:set_leader, true = leader_status}, state) do
    Logger.warning("Node: #{Node.self()} is a leader")

    for child <- Application.get_env(:gust, :leader_only_children, @default_children) do
      DynamicSupervisor.start_child(Gust.LeaderOnlySupervisor, child)
    end

    {:noreply, %{state | leader: leader_status}}
  end

  def handle_info(:attempt_lock, state) do
    attempt_lock()
    {:noreply, state}
  end
end
