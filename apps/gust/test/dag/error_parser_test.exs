defmodule Dag.ErrorParser do
  use Gust.DataCase
  import Gust.DAG.ErrorParser

  test "parse/1 when result does not have a reason" do
    error_msg = "ops.. something went wrong."
    error = %Ecto.Query.CastError{message: error_msg}

    assert parse(error) == %{
             type: "Ecto.Query.CastError",
             message: error_msg
           }
  end

  test "parse/1 parses non-recoverable errors" do
    error = %Gust.DAG.NonRecError{message: "invalid input"}

    assert parse(error) == %{
             type: "Gust.DAG.NonRecError",
             message: "invalid input"
           }
  end

  test "parse/1 includes a JSON-safe stacktrace when provided" do
    error = %RuntimeError{message: "ops"}

    stacktrace = [
      {Example.Task, :run, 1, [file: ~c"lib/example/task.ex", line: 42, column: 7]},
      {Enum, :map, [:items, :callback], [file: ~c"lib/enum.ex", line: 1714]}
    ]

    assert parse({:error_with_stacktrace, error, stacktrace}) == %{
             type: "RuntimeError",
             message: "ops",
             stacktrace: [
               %{
                 module: "Example.Task",
                 function: "run",
                 arity: 1,
                 file: "lib/example/task.ex",
                 line: 42,
                 column: 7
               },
               %{
                 module: "Enum",
                 function: "map",
                 arity: 2,
                 file: "lib/enum.ex",
                 line: 1714
               }
             ]
           }
  end

  test "parse/1 supports frames without files and with binary files" do
    error = %ArgumentError{message: "not an integer"}

    stacktrace = [
      {:erlang, :binary_to_integer, ["invalid"], [error_info: %{module: :erl_erts_errors}]},
      {Example.Task, :run, 0, [file: "lib/example/task.ex", line: 12]}
    ]

    assert parse({:error_with_stacktrace, error, stacktrace}).stacktrace == [
             %{
               module: ":erlang",
               function: "binary_to_integer",
               arity: 1
             },
             %{
               module: "Example.Task",
               function: "run",
               arity: 0,
               file: "lib/example/task.ex",
               line: 12
             }
           ]
  end
end
