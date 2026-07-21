defmodule Gust.DAG.NonRecError do
  @moduledoc """
  An error that fails a DAG task immediately without retrying it.

  Raise it from DAG code with:

      raise Gust.DAG.NonRecError, "input is invalid"
  """

  defexception message: "non-recoverable DAG task error"
end
