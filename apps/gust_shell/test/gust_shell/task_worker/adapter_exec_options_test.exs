defmodule GustShell.TaskWorker.AdapterExecOptionsTest do
  @moduledoc """
  Exercises parsed execution options through the shell worker and erlexec.
  Option normalization and invalid values are covered by Parser.AdapterOptionsTest.
  """

  use ExUnit.Case, async: false

  alias GustShell.TaskWorker.Adapter

  import Mox
  import GustShell.TestFixtures
  import GustShell.TaskWorkerHelpers, only: [await_exit: 1]

  setup :verify_on_exit!

  setup do
    Gust.DAGLoggerMock
    |> stub(:set_task, fn _, _ -> :ok end)
    |> stub(:unset, fn -> :ok end)

    :ok
  end

  for {option, command, stdout, stderr} <- [
        {"cd: /", "pwd", "/\n", ""},
        {"cwd: /", "pwd", "/\n", ""},
        {"working_dir: /", "pwd", "/\n", ""},
        {"env: {GREETING: hello}", "printf '%s' \"$GREETING\"", "hello", ""},
        {"executable: /bin/sh", "printf hello", "hello", ""},
        {"group: 0", "printf hello", "hello", ""},
        {"debug: 2", "printf hello", "hello", ""},
        {"kill_timeout: 2", "printf hello", "hello", ""},
        {"nice: 0", "printf hello", "hello", ""},
        {"pty: false", "test ! -t 1 && printf pipe", "pipe", ""},
        {"pty_echo: true", "printf hello", "hello", ""},
        {"pty_echo: false", "printf hello", "hello", ""},
        {"stdin: 'null'", "cat; printf eof", "eof", ""},
        {"stdin: close", "cat; printf eof", "eof", :closed_descriptor},
        {"stdin: /dev/null", "cat; printf eof", "eof", ""},
        {"stdout: close", "printf hidden; printf visible >&2", "", :closed_descriptor},
        {"stdout: 'null'", "printf hidden; printf visible >&2", "", "visible"},
        {"stdout: /dev/null", "printf hidden; printf visible >&2", "", "visible"},
        {"stderr: /dev/null", "printf visible; printf hidden >&2", "visible", ""},
        {"stderr: 'null'", "printf visible; printf hidden >&2", "visible", ""},
        {"stderr: close", "if printf hidden >&2; then printf open; else printf closed; fi",
         "closed", ""},
        {"success_exit_code: 0", "printf hello", "hello", ""}
      ] do
    test "executes parsed #{option}" do
      assert {:ok, definition} =
               parse_shell_dag("""
               tasks:
                 - name: configured
                   run: #{unquote(command)}
                   #{unquote(option)}
               """)

      state = %{
        task: %{id: 125, attempt: 1, name: "configured", params: %{}},
        owner_pid: self(),
        opts: Map.fetch!(definition.tasks, "configured")
      }

      assert {:noreply, running} = Adapter.handle_info(:run, state)
      on_exit(fn -> :exec.stop(running.os_pid) end)
      await_exit(running)

      assert_receive {:task_result, %{stdout: unquote(stdout), stderr: actual_stderr}, 125,
                      result}

      if unquote(stderr) == :closed_descriptor do
        assert actual_stderr =~ "file descriptor"
        assert result == :ok
      else
        assert actual_stderr == unquote(stderr)
        assert result == :ok
      end
    end
  end

  for echo <- [true, false] do
    test "allocates a terminal with pty_echo: #{echo}" do
      assert {:ok, definition} =
               parse_shell_dag("""
               tasks:
                 - name: terminal
                   run: test -t 1 && printf terminal
                   pty: true
                   pty_echo: #{unquote(echo)}
               """)

      state = %{
        task: %{id: 126, attempt: 1, name: "terminal", params: %{}},
        owner_pid: self(),
        opts: Map.fetch!(definition.tasks, "terminal")
      }

      assert {:noreply, running} = Adapter.handle_info(:run, state)
      on_exit(fn -> :exec.stop(running.os_pid) end)
      await_exit(running)

      assert_receive {:task_result, %{stdout: stdout, stderr: stderr, exit_code: 0}, 126, :ok}
      # A PTY shares stdout and stderr; erlexec may report its output on either stream.
      assert stdout <> stderr == "terminal"
    end
  end

  describe "cgroup option" do
    @tag :linux_only
    test "is parsed and passed to erlexec" do
      assert {:ok, definition} =
               parse_shell_dag("tasks: [{name: cgroup, run: echo test, cgroup: my_cgroup}]")

      state = %{
        task: %{id: 127, attempt: 1, name: "cgroup", params: %{}},
        owner_pid: self(),
        opts: Map.fetch!(definition.tasks, "cgroup")
      }

      assert {:noreply, running} = Adapter.handle_info(:run, state)
      on_exit(fn -> :exec.stop(running.os_pid) end)
      await_exit(running)

      assert_receive {:task_result, %{exit_code: 0}, 127, :ok}
    end
  end
end
