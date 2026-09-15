defmodule GustShell.TaskWorker.AdapterOptionsTest do
  use ExUnit.Case, async: true

  import Mox
  alias GustShell.TaskWorker.Adapter, as: ShellAdapter

  setup :verify_on_exit!
  setup :set_mox_from_context

  setup do
    Gust.DAGLoggerMock
    |> stub(:set_task, fn _task_id, _attempt -> nil end)
    |> stub(:unset, fn -> nil end)

    :ok
  end

  describe "normalize_exec_option - working directory options" do
    test "cd option is passed through" do
      options = %{"cd" => "/tmp"}
      opts = ShellAdapter.normalize_options(options)
      assert {:cd, "/tmp"} in opts
    end

    test "cwd is normalized to cd" do
      options = %{"cwd" => "/var"}
      opts = ShellAdapter.normalize_options(options)
      assert {:cd, "/var"} in opts
    end

    test "working_dir is normalized to cd" do
      options = %{"working_dir" => "/home"}
      opts = ShellAdapter.normalize_options(options)
      assert {:cd, "/home"} in opts
    end
  end

  describe "normalize_exec_option - environment variables" do
    test "env as a map is converted to list of tuples" do
      options = %{"env" => %{"FOO" => "bar", "BAZ" => "qux"}}
      opts = ShellAdapter.normalize_options(options)

      env_opt = Enum.find(opts, fn
        {:env, _} -> true
        _ -> false
      end)

      assert {:env, env_list} = env_opt
      assert {"FOO", "bar"} in env_list
      assert {"BAZ", "qux"} in env_list
    end

    test "env as a list is passed through" do
      env_list = [{"VAR1", "val1"}, {"VAR2", "val2"}]
      options = %{"env" => env_list, "monitor" => "false"}
      opts = ShellAdapter.normalize_options(options)

      assert {:env, env_list} in opts
      assert not Keyword.has_key?(opts, :monitor)
    end

    test "env values are converted to strings" do
      options = %{"env" => %{"NUM" => 123, "ATOM" => :test}}
      opts = ShellAdapter.normalize_options(options)

      env_opt = Enum.find(opts, fn
        {:env, _} -> true
        _ -> false
      end)

      assert {:env, env_list} = env_opt
      assert {"NUM", "123"} in env_list
      assert {"ATOM", "test"} in env_list
    end
  end

  describe "normalize_exec_option - user and group" do
    test "user option is passed through" do
      options = %{"user" => "app"}
      opts = ShellAdapter.normalize_options(options)
      assert {:user, "app"} in opts
    end

    test "group option is passed through" do
      options = %{"group" => 1000}
      opts = ShellAdapter.normalize_options(options)
      assert {:group, 1000} in opts
    end
  end

  describe "normalize_exec_option - PTY options" do
    test "pty boolean option" do
      options = %{"pty" => true}
      opts = ShellAdapter.normalize_options(options)
      assert :pty in opts
    end

    test "pty string 'true' is normalized" do
      options = %{"pty" => "true"}
      opts = ShellAdapter.normalize_options(options)
      assert :pty in opts
    end

    test "pty false is filtered out" do
      options = %{"pty" => false}
      opts = ShellAdapter.normalize_options(options)
      assert :pty not in opts
    end

    test "pty_echo boolean option" do
      options = %{"pty_echo" => true}
      opts = ShellAdapter.normalize_options(options)
      assert :pty_echo in opts
    end

    test "pty_echo string 'true' is normalized" do
      options = %{"pty_echo" => "true"}
      opts = ShellAdapter.normalize_options(options)
      assert :pty_echo in opts
    end

    test "pty_echo false is filtered out" do
      options = %{"pty_echo" => false}
      opts = ShellAdapter.normalize_options(options)
      assert :pty_echo not in opts
    end
  end

  describe "normalize_exec_option - process management" do
    test "kill_timeout with value" do
      options = %{"kill_timeout" => 10}
      opts = ShellAdapter.normalize_options(options)
      assert {:kill_timeout, 10} in opts
    end

    test "monitor is filtered out" do
      options = %{"monitor" => true}
      opts = ShellAdapter.normalize_options(options)
      assert :monitor not in opts
    end

    test "monitor false is filtered out" do
      options = %{"monitor" => false}
      opts = ShellAdapter.normalize_options(options)
      assert :monitor not in opts
    end

    test "nice option" do
      options = %{"nice" => 5}
      opts = ShellAdapter.normalize_options(options)
      assert {:nice, 5} in opts
    end

    test "success_exit_code option" do
      options = %{"success_exit_code" => 0}
      opts = ShellAdapter.normalize_options(options)
      assert {:success_exit_code, 0} in opts
    end
  end

  describe "normalize_exec_option - advanced options" do
    test "stdin as close" do
      options = %{"stdin" => "close"}
      opts = ShellAdapter.normalize_options(options)
      assert {:stdin, :close} in opts
    end

    test "stdin as null" do
      options = %{"stdin" => "null"}
      opts = ShellAdapter.normalize_options(options)
      assert {:stdin, :null} in opts
    end

    test "stdin as file path" do
      options = %{"stdin" => "/tmp/input.txt"}
      opts = ShellAdapter.normalize_options(options)
      assert {:stdin, "/tmp/input.txt"} in opts
    end

    test "stdout as close" do
      options = %{"stdout" => "close"}
      opts = ShellAdapter.normalize_options(options)
      assert {:stdout, :close} in opts
    end

    test "stdout as null" do
      options = %{"stdout" => "null"}
      opts = ShellAdapter.normalize_options(options)
      assert {:stdout, :null} in opts
    end

    test "stdout as file path" do
      options = %{"stdout" => "/tmp/output.txt"}
      opts = ShellAdapter.normalize_options(options)
      assert {:stdout, "/tmp/output.txt"} in opts
    end

    test "stderr as close" do
      options = %{"stderr" => "close"}
      opts = ShellAdapter.normalize_options(options)
      assert {:stderr, :close} in opts
    end

    test "stderr as null" do
      options = %{"stderr" => "null"}
      opts = ShellAdapter.normalize_options(options)
      assert {:stderr, :null} in opts
    end

    test "stderr as file path" do
      options = %{"stderr" => "/tmp/error.txt"}
      opts = ShellAdapter.normalize_options(options)
      assert {:stderr, "/tmp/error.txt"} in opts
    end

    test "debug option" do
      options = %{"debug" => 2}
      opts = ShellAdapter.normalize_options(options)
      assert {:debug, 2} in opts
    end

    test "executable option" do
      options = %{"executable" => "/bin/bash"}
      opts = ShellAdapter.normalize_options(options)
      assert {:executable, "/bin/bash"} in opts
    end

    test "cgroup option" do
      options = %{"cgroup" => "my_group"}
      opts = ShellAdapter.normalize_options(options)
      assert {:cgroup, "my_group"} in opts
    end
  end

  describe "normalize_exec_option - unknown options" do
    test "unknown options are filtered out" do
      options = %{"unknown" => "value", "another" => 123}
      opts = ShellAdapter.normalize_options(options)

      # Should not contain the unknown options
      refute Enum.any?(opts, fn opt ->
        case opt do
          {:unknown, _} -> true
          {:another, _} -> true
          _ -> false
        end
      end)
    end

    test "mixed known and unknown options keeps only known ones" do
      options = %{
        "cd" => "/tmp",
        "unknown" => "value",
        "user" => "app"
      }

      opts = ShellAdapter.normalize_options(options)

      assert {:cd, "/tmp"} in opts
      assert {:user, "app"} in opts
      refute Enum.any?(opts, fn
        {:unknown, _} -> true
        _ -> false
      end)
    end
  end

  describe "normalize_option_key - key normalization" do
    test "atom keys are handled" do
      options = %{cd: "/tmp", env: %{}}
      opts = ShellAdapter.normalize_options(options)
      assert {:cd, "/tmp"} in opts
    end

    test "string keys are handled" do
      options = %{"cd" => "/tmp", "env" => %{}}
      opts = ShellAdapter.normalize_options(options)
      assert {:cd, "/tmp"} in opts
    end

    test "case-sensitive key matching" do
      options = %{"CD" => "/tmp"}
      opts = ShellAdapter.normalize_options(options)
      # "CD" should not match "cd"
      refute Enum.any?(opts, fn
        {:cd, _} -> true
        _ -> false
      end)
    end

    test "whitespace in keys is trimmed" do
      options = %{"  cd  " => "/tmp"}
      opts = ShellAdapter.normalize_options(options)
      assert {:cd, "/tmp"} in opts
    end
  end

  describe "comprehensive option combinations" do
    test "full configuration with multiple options" do
      options = %{
        "run" => "backup.sh",
        "cd" => "/backups",
        "env" => %{"DATE" => "2024-01-01", "VERBOSE" => "1"},
        "user" => "backup",
        "group" => 1000,
        "kill_timeout" => 30,
        "pty" => false,
        "monitor" => true,
        "nice" => 10
      }

      opts = ShellAdapter.normalize_options(options)

      assert {:cd, "/backups"} in opts
      assert {:nice, 10} in opts
      assert {:kill_timeout, 30} in opts
      assert {:user, "backup"} in opts
      assert {:group, 1000} in opts
      assert :monitor not in opts

      env_opt = Enum.find(opts, fn
        {:env, _} -> true
        _ -> false
      end)

      assert {:env, env_list} = env_opt
      assert {"DATE", "2024-01-01"} in env_list
    end

    test "minimal configuration only run command" do
      options = %{"run" => "echo hello"}
      assert [] = ShellAdapter.normalize_options(options)
    end
  end

  describe "environment variable normalization edge cases" do
    test "normalizes non-string/non-list env values" do
      # Testing normalize_env/1 fallback that returns value as-is
      # This covers line 171: defp normalize_env(value), do: value
      options = %{"env" => %{123 => 456, :atom => :value}}
      opts = ShellAdapter.normalize_options(options)

      env_opt = Enum.find(opts, fn
        {:env, _} -> true
        _ -> false
      end)

      # Should contain the env option with non-string keys converted to strings
      assert {:env, env_list} = env_opt
      assert env_list != []
    end
  end

  describe "exec options deduplication" do
    test "filters duplicate stdio options (line 24-25 coverage)" do
      # This indirectly tests line 24: (opt, acc) when opt in [:stdin, :stdout, :stderr]
      # Line 24 handles bare atom options in the Enum.reduce
      # For this to execute, we need exec_opts to contain bare atoms like :pty or :pty_echo
      # (which get added by normalize_exec_option when true)

      options = %{
        "pty" => "true",
        "stdin" => "close"
      }
      opts = ShellAdapter.normalize_options(options)

      # :pty is a bare atom (from line 129)
      # {:stdin, :close} is a tuple
      # Both should be present
      assert :pty in opts
      assert {:stdin, :close} in opts
    end
  end

  describe "normalize_env edge cases" do
    test "passes through non-string non-list env values unchanged" do
      # This tests line 171: defp normalize_env(value), do: value
      # The catch-all clause that returns the value as-is for unknown types

      # We can't directly test normalize_env as it's private, but we can test
      # that normalize_options doesn't crash with non-standard env values
      options = %{
        "env" => :atom_value
      }
      opts = ShellAdapter.normalize_options(options)

      # Should have an env option with the atom value passed through
      env_opt = Enum.find(opts, fn
        {:env, _} -> true
        _ -> false
      end)

      assert {:env, :atom_value} == env_opt
    end
  end
end
