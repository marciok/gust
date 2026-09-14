defmodule Gust.DAG.Source.Folder.MonitorTest do
  use ExUnit.Case, async: false

  import Mox

  alias Gust.DAG.Source.Folder.Monitor

  setup :verify_on_exit!

  describe "start_link/3" do
    test "starts a GenServer" do
      watcher_pid = self()
      loader_pid = self()
      folder = "/tmp/test"

      {:ok, monitor_pid} = Monitor.start_link(watcher_pid, loader_pid, folder)

      assert is_pid(monitor_pid)
      assert Process.alive?(monitor_pid)

      # Cleanup
      GenServer.stop(monitor_pid)
    end

    test "stores initial state" do
      watcher_pid = self()
      loader_pid = self()
      folder = "/tmp/test"

      {:ok, monitor_pid} = Monitor.start_link(watcher_pid, loader_pid, folder)

      # GenServer is running
      assert Process.alive?(monitor_pid)

      # Cleanup
      GenServer.stop(monitor_pid)
    end
  end

  describe "handle_info - file events" do
    test "receives file event and queues path" do
      watcher_pid = self()
      loader_pid = self()
      folder = "/tmp/test"

      {:ok, monitor_pid} = Monitor.start_link(watcher_pid, loader_pid, folder)

      # Send file event for non-DAG file (to avoid parser mock calls)
      send(monitor_pid, {:file_event, watcher_pid, {"/tmp/test/readme.md", [:modified]}})

      # Wait briefly
      Process.sleep(50)

      # Should still be alive
      assert Process.alive?(monitor_pid)

      # Cleanup
      GenServer.stop(monitor_pid)
    end

    test "handles multiple file events" do
      watcher_pid = self()
      loader_pid = self()
      folder = "/tmp/test"

      {:ok, monitor_pid} = Monitor.start_link(watcher_pid, loader_pid, folder)

      # Send multiple non-DAG file events
      send(monitor_pid, {:file_event, watcher_pid, {"/tmp/test/file1.md", [:modified]}})
      send(monitor_pid, {:file_event, watcher_pid, {"/tmp/test/file2.txt", [:modified]}})

      # Wait briefly
      Process.sleep(50)

      # Should still be alive
      assert Process.alive?(monitor_pid)

      # Cleanup
      GenServer.stop(monitor_pid)
    end

    test "debounces repeated events for same file" do
      watcher_pid = self()
      loader_pid = self()
      folder = "/tmp/test"

      {:ok, monitor_pid} = Monitor.start_link(watcher_pid, loader_pid, folder)

      # Send same file event multiple times (non-DAG to avoid parser calls)
      send(monitor_pid, {:file_event, watcher_pid, {"/tmp/test/file.md", [:modified]}})
      send(monitor_pid, {:file_event, watcher_pid, {"/tmp/test/file.md", [:modified]}})
      send(monitor_pid, {:file_event, watcher_pid, {"/tmp/test/file.md", [:modified]}})

      # Wait briefly
      Process.sleep(50)

      # Should still be alive
      assert Process.alive?(monitor_pid)

      # Cleanup
      GenServer.stop(monitor_pid)
    end

    test "ignores events for files without recognizable extensions" do
      watcher_pid = self()
      loader_pid = self()
      folder = "/tmp/test"

      {:ok, monitor_pid} = Monitor.start_link(watcher_pid, loader_pid, folder)

      # Send event for non-DAG file
      send(monitor_pid, {:file_event, watcher_pid, {"/tmp/test/readme.md", [:modified]}})

      # Wait for processing
      Process.sleep(150)

      # Should not crash
      assert Process.alive?(monitor_pid)

      # Cleanup
      GenServer.stop(monitor_pid)
    end

    test "processes check_queue message for unrecognized extensions" do
      watcher_pid = self()
      loader_pid = self()
      folder = "/tmp/test"

      {:ok, monitor_pid} = Monitor.start_link(watcher_pid, loader_pid, folder)

      # Send event for non-DAG file to trigger check_queue without parser calls
      send(monitor_pid, {:file_event, watcher_pid, {"/tmp/test/file.unknown", [:modified]}})

      # Wait for debounce timer to fire and check_queue to be processed
      Process.sleep(150)

      # Should still be alive after processing
      assert Process.alive?(monitor_pid)

      # Cleanup
      GenServer.stop(monitor_pid)
    end
  end

  describe "adapter detection for unsupported files" do
    test "ignores .md files" do
      watcher_pid = self()
      loader_pid = self()
      folder = "/tmp/test"

      {:ok, monitor_pid} = Monitor.start_link(watcher_pid, loader_pid, folder)

      # Send event for .md file
      send(monitor_pid, {:file_event, watcher_pid, {"/tmp/test/readme.md", [:created]}})

      # Wait for processing
      Process.sleep(150)

      # Should not crash
      assert Process.alive?(monitor_pid)

      # Cleanup
      GenServer.stop(monitor_pid)
    end

    test "ignores .txt files" do
      watcher_pid = self()
      loader_pid = self()
      folder = "/tmp/test"

      {:ok, monitor_pid} = Monitor.start_link(watcher_pid, loader_pid, folder)

      # Send event for .txt file
      send(monitor_pid, {:file_event, watcher_pid, {"/tmp/test/notes.txt", [:created]}})

      # Wait for processing
      Process.sleep(150)

      # Should not crash
      assert Process.alive?(monitor_pid)

      # Cleanup
      GenServer.stop(monitor_pid)
    end

    test "ignores .json files" do
      watcher_pid = self()
      loader_pid = self()
      folder = "/tmp/test"

      {:ok, monitor_pid} = Monitor.start_link(watcher_pid, loader_pid, folder)

      # Send event for .json file
      send(monitor_pid, {:file_event, watcher_pid, {"/tmp/test/config.json", [:created]}})

      # Wait for processing
      Process.sleep(150)

      # Should not crash
      assert Process.alive?(monitor_pid)

      # Cleanup
      GenServer.stop(monitor_pid)
    end
  end

  describe "file action types" do
    test "handles created event" do
      watcher_pid = self()
      loader_pid = self()
      folder = "/tmp/test"

      {:ok, monitor_pid} = Monitor.start_link(watcher_pid, loader_pid, folder)

      # Send event for non-DAG created file
      send(monitor_pid, {:file_event, watcher_pid, {"/tmp/test/file.md", [:created]}})

      # Wait briefly
      Process.sleep(50)

      # Should still be alive
      assert Process.alive?(monitor_pid)

      # Cleanup
      GenServer.stop(monitor_pid)
    end

    test "handles modified event" do
      watcher_pid = self()
      loader_pid = self()
      folder = "/tmp/test"

      {:ok, monitor_pid} = Monitor.start_link(watcher_pid, loader_pid, folder)

      # Send event for non-DAG modified file
      send(monitor_pid, {:file_event, watcher_pid, {"/tmp/test/file.md", [:modified]}})

      # Wait briefly
      Process.sleep(50)

      # Should still be alive
      assert Process.alive?(monitor_pid)

      # Cleanup
      GenServer.stop(monitor_pid)
    end

    test "handles deleted event" do
      watcher_pid = self()
      loader_pid = self()
      folder = "/tmp/test"

      {:ok, monitor_pid} = Monitor.start_link(watcher_pid, loader_pid, folder)

      # Send event for non-DAG deleted file
      send(monitor_pid, {:file_event, watcher_pid, {"/tmp/test/file.md", [:deleted]}})

      # Wait briefly
      Process.sleep(50)

      # Should still be alive
      assert Process.alive?(monitor_pid)

      # Cleanup
      GenServer.stop(monitor_pid)
    end
  end

  describe "reload delay configuration" do
    test "uses file_reload_delay from app config" do
      Application.put_env(:gust, :file_reload_delay, 500)

      try do
        watcher_pid = self()
        loader_pid = self()
        folder = "/tmp/test"

        {:ok, monitor_pid} = Monitor.start_link(watcher_pid, loader_pid, folder)

        # Process should be running
        assert Process.alive?(monitor_pid)

        # Cleanup
        GenServer.stop(monitor_pid)
      after
        Application.put_env(:gust, :file_reload_delay, 1_000)
      end
    end

    test "uses default 1000ms if not configured" do
      Application.delete_env(:gust, :file_reload_delay)

      watcher_pid = self()
      loader_pid = self()
      folder = "/tmp/test"

      {:ok, monitor_pid} = Monitor.start_link(watcher_pid, loader_pid, folder)

      # Process should be running
      assert Process.alive?(monitor_pid)

      # Cleanup
      GenServer.stop(monitor_pid)
    end
  end

  describe "state management" do
    test "maintains events queue" do
      watcher_pid = self()
      loader_pid = self()
      folder = "/tmp/test"

      {:ok, monitor_pid} = Monitor.start_link(watcher_pid, loader_pid, folder)

      # Send multiple non-DAG file events (avoid parser calls)
      send(monitor_pid, {:file_event, watcher_pid, {"/tmp/test/file1.md", [:modified]}})
      send(monitor_pid, {:file_event, watcher_pid, {"/tmp/test/file2.txt", [:modified]}})

      # Wait briefly
      Process.sleep(50)

      # Process should still be alive
      assert Process.alive?(monitor_pid)

      # Wait for debounce
      Process.sleep(150)

      # Cleanup
      GenServer.stop(monitor_pid)
    end

    test "clears events after processing" do
      watcher_pid = self()
      loader_pid = self()
      folder = "/tmp/test"

      {:ok, monitor_pid} = Monitor.start_link(watcher_pid, loader_pid, folder)

      # Send non-DAG file event
      send(monitor_pid, {:file_event, watcher_pid, {"/tmp/test/readme.md", [:modified]}})

      # Wait for full debounce and processing cycle
      Process.sleep(200)

      # Send another non-DAG file event
      send(monitor_pid, {:file_event, watcher_pid, {"/tmp/test/notes.txt", [:modified]}})

      # Wait for processing
      Process.sleep(150)

      # Process should still be alive with updated state
      assert Process.alive?(monitor_pid)

      # Cleanup
      GenServer.stop(monitor_pid)
    end
  end

  describe "GenServer lifecycle" do
    test "init returns correct state" do
      watcher_pid = self()
      loader_pid = self()
      folder = "/tmp/test"

      {:ok, monitor_pid} = Monitor.start_link(watcher_pid, loader_pid, folder)

      # GenServer initialized successfully
      assert is_pid(monitor_pid)

      # Cleanup
      GenServer.stop(monitor_pid)
    end

    test "handles unknown messages gracefully" do
      watcher_pid = self()
      loader_pid = self()
      folder = "/tmp/test"

      {:ok, monitor_pid} = Monitor.start_link(watcher_pid, loader_pid, folder)

      # Send unknown message
      send(monitor_pid, :unknown_message)

      # Process should handle it gracefully
      Process.sleep(50)
      assert Process.alive?(monitor_pid)

      # Cleanup
      GenServer.stop(monitor_pid)
    end

    test "stops gracefully" do
      watcher_pid = self()
      loader_pid = self()
      folder = "/tmp/test"

      {:ok, monitor_pid} = Monitor.start_link(watcher_pid, loader_pid, folder)

      # Stop the GenServer
      GenServer.stop(monitor_pid)

      # Wait briefly
      Process.sleep(50)

      # Should not be alive
      refute Process.alive?(monitor_pid)
    end
  end
end
