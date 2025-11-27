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
end
