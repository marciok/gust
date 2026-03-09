defmodule GustPy.TaskWorker.Error do
  @moduledoc false

  defexception [:type, :reason, message: "GustPy task error"]

  @type t :: %__MODULE__{
          type: atom() | String.t(),
          reason: term(),
          message: String.t()
        }

  @spec new(atom() | String.t(), term()) :: t()
  def new(type, reason) do
    %__MODULE__{
      type: type,
      reason: reason,
      message: format_message(type, reason)
    }
  end

  defp format_message(type, reason) do
    "#{to_string(type)}: #{format_reason(reason)}"
  end

  defp format_reason(reason) when is_binary(reason), do: reason
end
