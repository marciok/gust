defmodule Gust.DAG.ErrorParser do
  @moduledoc false

  def parse({:error_with_stacktrace, error, stacktrace}) do
    error
    |> parse()
    |> Map.put(:stacktrace, parse_stacktrace(stacktrace))
  end

  def parse(error) do
    %{
      type: inspect(error.__struct__),
      message: Exception.message(error)
    }
  end

  defp parse_stacktrace(stacktrace) do
    Enum.map(stacktrace, fn
      {module, function, arity_or_args, location} ->
        %{
          module: inspect(module),
          function: to_string(function),
          arity: stacktrace_arity(arity_or_args),
          file: file_description(location[:file]),
          line: location[:line],
          column: location[:column]
        }
        |> Map.reject(fn {_key, value} -> is_nil(value) end)
    end)
  end

  defp stacktrace_arity(arity) when is_integer(arity), do: arity
  defp stacktrace_arity(args) when is_list(args), do: length(args)

  defp file_description(nil), do: nil
  defp file_description(file) when is_binary(file), do: file
  defp file_description(file) when is_list(file), do: List.to_string(file)
end
