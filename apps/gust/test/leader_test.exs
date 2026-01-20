defmodule LeaderTest do
  alias Gust.Leader
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog
  import Mox

  setup :verify_on_exit!
  setup :set_mox_from_context

  defmodule LeaderOnlyChildren do
    @moduledoc false
    use GenServer

    def init(init_arg) do
      {:ok, init_arg}
    end

    def start_link(arg) do
      GenServer.start_link(__MODULE__, arg)
    end
  end

  describe "handle_continue/2 when message :attempt_lock is passed" do
    test "process is set as follower" do
      start_supervised!(
        {DynamicSupervisor, strategy: :one_for_one, name: Gust.LeaderOnlySupervisor}
      )

      retry_delay = 200
      Application.put_env(:gust, :leader_lock_attempt, retry_delay)
      Application.put_env(:gust, :leader_only_children, [LeaderOnlyChildren])

      Gust.DBLockerMock
      |> expect(:try_lock, fn _key, result_fn -> result_fn.(false) end)
      |> expect(:try_lock, fn _key, result_fn -> result_fn.(true) end)

      {pid, logs} =
        with_log(fn ->
          pid = start_link_supervised!(Leader)
          Process.sleep(retry_delay - 50)

          assert GenServer.call(pid, :leader?) == false

          Process.sleep(retry_delay + 50)
          assert GenServer.call(pid, :leader?) == true
          pid
        end)

      assert logs =~ "Node: #{Node.self()} is a follower"
      assert logs =~ "Node: #{Node.self()} is a leader"

      assert [{_, _, :worker, [LeaderOnlyChildren]}] =
               DynamicSupervisor.which_children(Gust.LeaderOnlySupervisor)

      with_log(fn ->
        send(pid, {:set_leader, false})
      end)

      Process.sleep(50)
      assert [] = DynamicSupervisor.which_children(Gust.LeaderOnlySupervisor)
    end
  end
end
