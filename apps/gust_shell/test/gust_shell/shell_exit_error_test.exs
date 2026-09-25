defmodule GustShell.ShellExitErrorTest do
  use ExUnit.Case, async: true

  describe "ShellExitError exception" do
    test "creates an exception with exit code" do
      error = %GustShell.ShellExitError{
        exit_code: 1,
        stdout: "output",
        stderr: "error"
      }

      assert is_exception(error)
      assert Exception.message(error) =~ "command exited with code 1"
    end

    test "includes stdout and stderr in message" do
      error = %GustShell.ShellExitError{
        exit_code: 127,
        stdout: "command not found",
        stderr: "error output"
      }

      assert "command exited with code 127\nstdout: command not found; stderr: error output" =
        Exception.message(error)
    end

    test "indicates core dump in message" do
      error = %GustShell.ShellExitError{
        exit_code: 9,
        stdout: "",
        stderr: "",
        coredump: true
      }

      assert "command exited with code 9 (core dumped)" = Exception.message(error)
    end

    test "indicates core dump in message with nil stdout and stderr" do
      error = %GustShell.ShellExitError{
        exit_code: 1,
        stdout: nil,
        stderr: nil,
        coredump: false
      }

      assert "command exited with code 1" = Exception.message(error)
    end

    test "truncates long output in message" do
      long_output = String.duplicate("x", 500)

      error = %GustShell.ShellExitError{
        exit_code: 1,
        stdout: long_output,
        stderr: ""
      }

      message = Exception.message(error)
      # Message should be truncated to 200 chars per line
      assert byte_size(message) < byte_size(long_output)
    end

    test "can be used with ErrorParser.parse/1" do
      error = %GustShell.ShellExitError{
        exit_code: 1,
        stdout: "test output",
        stderr: "test error"
      }

      # This should not crash; ErrorParser expects a __struct__ field
      assert error.__struct__ == GustShell.ShellExitError
      assert "command exited with code 1\nstdout: test output; stderr: test error" = Exception.message(error)
    end
  end
end
