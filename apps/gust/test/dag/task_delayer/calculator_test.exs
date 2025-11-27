defmodule DAG.TaskDelayer.CalculatorTest do
  alias Gust.DAG.TaskDelayer.Calculator
  use Gust.DataCase

  test "calc_delay/1" do
    attempt = 3
    assert 20_000 = Calculator.calc_delay(attempt)
  end
end
