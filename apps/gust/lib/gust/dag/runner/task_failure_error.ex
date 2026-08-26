defmodule Gust.DAG.Runner.TaskFailureError do
  defexception [:message]

  @type t :: %__MODULE__{message: String.t() | nil}

  @spec exception_from_error(Exception.t()) :: t()
  def exception_from_error(error) do
    exception("#{inspect(error.__struct__)}\n message: #{Exception.message(error)}")
  end
end
