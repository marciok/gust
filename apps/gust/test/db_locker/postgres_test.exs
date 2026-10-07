defmodule DBLocker.PostgresTest do
  alias Gust.DBLocker.Postgres
  alias Gust.Repo
  use Gust.DataCase, async: false

  @app_name "gust_db_locker_test"

  setup do
    previous = Application.get_env(:gust, :db_locker_connection)
    Application.put_env(:gust, :db_locker_connection, parameters: [application_name: @app_name])

    on_exit(fn ->
      if previous,
        do: Application.put_env(:gust, :db_locker_connection, previous),
        else: Application.delete_env(:gust, :db_locker_connection)
    end)
  end

  describe "try_lock/2" do
    test "only one contender holds the lock until it releases its connection" do
      parent = self()

      holder =
        Task.async(fn ->
          Postgres.try_lock(12_349, fn success ->
            send(parent, {:holder_acquired, success})

            receive do
              :release -> :ok
            end
          end)
        end)

      try do
        assert_receive {:holder_acquired, true}, 5_000

        results =
          1..3
          |> Task.async_stream(fn _ -> Postgres.try_lock(12_349, & &1) end,
            timeout: :infinity
          )
          |> Enum.to_list()

        assert results == [{:ok, false}, {:ok, false}, {:ok, false}]
      after
        send(holder.pid, :release)
        Task.await(holder)
      end

      wait_until(fn -> advisory_lock_holders() == 0 end)
      assert Postgres.try_lock(12_349, & &1)
    end

    test "acquires the lock on a dedicated connection and releases it afterwards" do
      Postgres.try_lock(12_345, fn attempt ->
        send(self(), {:result, attempt})
        send(self(), {:holders, advisory_lock_holders()})
      end)

      assert_receive {:result, true}
      assert_receive {:holders, 1}
      wait_until(fn -> advisory_lock_holders() == 0 end)

      Postgres.try_lock(12_345, &send(self(), {:result_again, &1}))
      assert_receive {:result_again, true}
    end

    test "does not acquire a lock held by another session" do
      {:ok, other} = Postgrex.start_link(Repo.connection_opts())
      Postgrex.query!(other, "SELECT pg_advisory_lock($1)", [12_346])

      Postgres.try_lock(12_346, &send(self(), {:result, &1}))
      assert_receive {:result, false}

      GenServer.stop(other)
    end

    @tag :capture_log
    test "exits the caller when the connection holding the lock drops" do
      {pid, ref} =
        spawn_monitor(fn ->
          Postgres.try_lock(12_347, fn true -> Process.sleep(:infinity) end)
        end)

      wait_until(fn -> advisory_lock_holders() == 1 end)

      Repo.query!("SELECT pg_stat_clear_snapshot()")

      Repo.query!(
        "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE application_name = $1",
        [@app_name]
      )

      assert_receive {:DOWN, ^ref, :process, ^pid, :killed}, 5_000
    end

    test "releases the lock when the callback raises" do
      assert_raise RuntimeError, "callback failed", fn ->
        Postgres.try_lock(12_348, fn true -> raise "callback failed" end)
      end

      wait_until(fn -> advisory_lock_holders() == 0 end)
      assert Postgres.try_lock(12_348, & &1)
    end
  end

  # Tests run inside a sandbox transaction, where pg_stat_activity is a snapshot
  # taken on first access.
  defp advisory_lock_holders do
    Repo.query!("SELECT pg_stat_clear_snapshot()")

    %{rows: [[count]]} =
      Repo.query!(
        """
        SELECT count(*) FROM pg_locks l
        JOIN pg_stat_activity a ON a.pid = l.pid
        WHERE l.locktype = 'advisory' AND l.granted AND a.application_name = $1
        """,
        [@app_name]
      )

    count
  end

  defp wait_until(fun, attempts \\ 50) do
    cond do
      fun.() ->
        :ok

      attempts == 0 ->
        flunk("condition not met")

      true ->
        Process.sleep(20)
        wait_until(fun, attempts - 1)
    end
  end
end
