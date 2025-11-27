defmodule DAG.Graph.CycleDectectionTest do
  alias Gust.DAG.Graph.CycleDection
  use Gust.DataCase

  test "error message" do
    assert_raise(CycleDection, "Possible cycle detected", fn -> raise CycleDection end)
  end
end
