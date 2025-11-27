defmodule Gust.Flows.RunTest do
  use ExUnit.Case, async: true
  alias Gust.Flows.Run

  test "rejects creation without dag_id" do
    changeset = Run.changeset(%Run{}, %{})
    refute changeset.valid?
  end
end
