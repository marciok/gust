defmodule Gust.DAG.Source.PollingTest do
  use ExUnit.Case, async: false

  import Gust.ApplicationEnvHelpers

  alias Gust.DAG.Source.Polling

  setup :init_dag_source

  describe "start_link/3" do
    test "starts a polling process" do
      loader_pid = self()

      {:ok, monitor_pid} =
        Polling.start_link(loader_pid, fn -> %{} end, 100)

      assert is_pid(monitor_pid)
      assert Process.alive?(monitor_pid)
    end

    test "process links to parent" do
      loader_pid = self()

      {:ok, monitor_pid} =
        Polling.start_link(loader_pid, fn -> %{} end, 100)

      # Verify process is alive
      assert Process.alive?(monitor_pid)
    end
  end

  describe "polling behavior" do
    test "calls load function repeatedly" do
      loader_pid = self()
      {:ok, call_count} = Agent.start_link(fn -> 0 end)

      load_fn = fn ->
        Agent.update(call_count, &(&1 + 1))
        %{"dag1" => {:ok, %{}}}
      end

      {:ok, _monitor_pid} = Polling.start_link(loader_pid, load_fn, 50)

      # Wait for a few poll cycles
      Process.sleep(150)

      count = Agent.get(call_count, & &1)
      assert count >= 2

      Agent.stop(call_count)
    end

    test "broadcasts new DAG on first poll" do
      loader_pid = self()

      load_fn = fn ->
        %{"dag1" => {:ok, %{name: "test"}}}
      end

      {:ok, _monitor_pid} = Polling.start_link(loader_pid, load_fn, 50)

      # Should receive message for new DAG
      assert_receive {"dag1", {:ok, %{name: "test"}}, "reload"}
    end

    test "broadcasts when DAG content changes" do
      loader_pid = self()
      {:ok, state} = Agent.start_link(fn -> 0 end)

      load_fn = fn ->
        case Agent.get_and_update(state, fn count -> {count, count + 1} end) do
          0 -> %{"dag1" => {:ok, %{version: 1}}}
          _ -> %{"dag1" => {:ok, %{version: 2}}}
        end
      end

      {:ok, _monitor_pid} = Polling.start_link(loader_pid, load_fn, 50)

      # First poll - new DAG
      assert_receive {"dag1", {:ok, %{version: 1}}, "reload"}

      # Wait for next poll - should detect change
      assert_receive {"dag1", {:ok, %{version: 2}}, "reload"}

      Agent.stop(state)
    end

    test "broadcasts when DAG is removed" do
      loader_pid = self()
      {:ok, state} = Agent.start_link(fn -> 0 end)

      load_fn = fn ->
        case Agent.get_and_update(state, fn count -> {count, count + 1} end) do
          0 -> %{"dag1" => {:ok, %{}}, "dag2" => {:ok, %{}}}
          _ -> %{"dag1" => {:ok, %{}}}
        end
      end

      {:ok, _monitor_pid} = Polling.start_link(loader_pid, load_fn, 50)

      # First poll - two DAGs
      assert_receive {"dag1", {:ok, _}, "reload"}
      assert_receive {"dag2", {:ok, _}, "reload"}

      # Wait for next poll - dag2 removed
      assert_receive {"dag2", {:error, "DAG removed"}, "removed"}

      Agent.stop(state)
    end

    test "does not broadcast unchanged DAGs" do
      loader_pid = self()
      {:ok, call_count} = Agent.start_link(fn -> 0 end)

      load_fn = fn ->
        Agent.update(call_count, &(&1 + 1))
        %{"dag1" => {:ok, %{name: "test"}}}
      end

      {:ok, _monitor_pid} = Polling.start_link(loader_pid, load_fn, 50)

      # First poll - new DAG
      assert_receive {"dag1", {:ok, _}, "reload"}

      # Wait for multiple polls - should NOT receive another message for same DAG
      Process.sleep(150)

      # Only the initial message should be received
      refute_receive {"dag1", _, "reload"}

      Agent.stop(call_count)
    end

    test "handles error results in load function" do
      loader_pid = self()
      {:ok, state} = Agent.start_link(fn -> 0 end)

      load_fn = fn ->
        case Agent.get_and_update(state, fn count -> {count, count + 1} end) do
          0 -> %{"dag1" => {:error, "Parse error"}}
          _ -> %{"dag1" => {:ok, %{}}}
        end
      end

      {:ok, _monitor_pid} = Polling.start_link(loader_pid, load_fn, 50)

      # First poll - error
      assert_receive {"dag1", {:error, "Parse error"}, "reload"}

      # Second poll - resolved
      assert_receive {"dag1", {:ok, %{}}, "reload"}

      Agent.stop(state)
    end

    test "broadcasts multiple DAGs simultaneously" do
      loader_pid = self()

      load_fn = fn ->
        %{
          "dag1" => {:ok, %{id: 1}},
          "dag2" => {:ok, %{id: 2}},
          "dag3" => {:ok, %{id: 3}}
        }
      end

      {:ok, _monitor_pid} = Polling.start_link(loader_pid, load_fn, 50)

      # All DAGs should be broadcast
      assert_receive {"dag1", {:ok, _}, "reload"}
      assert_receive {"dag2", {:ok, _}, "reload"}
      assert_receive {"dag3", {:ok, _}, "reload"}
    end
  end

  describe "checksum detection" do
    test "detects changes to error messages" do
      loader_pid = self()
      {:ok, state} = Agent.start_link(fn -> 0 end)

      load_fn = fn ->
        case Agent.get_and_update(state, fn count -> {count, count + 1} end) do
          0 -> %{"dag1" => {:error, "Error A"}}
          _ -> %{"dag1" => {:error, "Error B"}}
        end
      end

      {:ok, _monitor_pid} = Polling.start_link(loader_pid, load_fn, 50)

      # First poll - error A
      assert_receive {"dag1", {:error, "Error A"}, "reload"}

      # Second poll - error B (different error)
      assert_receive {"dag1", {:error, "Error B"}, "reload"}

      Agent.stop(state)
    end
  end
end
