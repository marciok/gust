defmodule GustShell.ShellExitError do
  @moduledoc """
  Exception raised when a shell command exits with a non-zero status or is killed by a signal.

  Preserves exit code, stdout, stderr, and coredump information for error reporting and logging.
  """

  defexception [:exit_code, :stdout, :stderr, :coredump]

  @type t :: %__MODULE__{
          exit_code: non_neg_integer(),
          stdout: String.t(),
          stderr: String.t(),
          coredump: boolean() | nil
        }

  @impl true
  def message(%__MODULE__{exit_code: code, coredump: coredump, stdout: out, stderr: err}) do
    details =
      [
        not_empty(out) && "stdout: #{String.slice(out, 0..200)}",
        not_empty(err) && "stderr: #{String.slice(err, 0..200)}"
      ]
      |> Enum.reject(&(is_nil(&1)))
      |> case do
        [] -> nil
        list -> "\n" <> Enum.join(list, "; ")
      end

    "command exited with code #{code}#{not_empty(coredump) && " (core dumped)"}#{details}"
  end

  defp not_empty(val) when val in [nil, "", false], do: nil
  defp not_empty(val), do: val
end
