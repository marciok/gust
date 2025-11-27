defmodule Gust.Flows.DagTest do
  use ExUnit.Case, async: true
  alias Gust.Flows.Dag

  describe "name format validation" do
    test "accepts valid names" do
      valid_names = ["some_name", "dag1", "abc_123"]

      for name <- valid_names do
        changeset = Dag.changeset(%Dag{}, %{name: name})
        assert changeset.valid?, "Expected #{name} to be valid, but got errors: #{inspect(changeset.errors)}"
      end
    end

    test "rejects invalid names" do
      invalid_names = ["SomeName", "some name", "some-name", "some$name", ""]

      for name <- invalid_names do
        changeset = Dag.changeset(%Dag{}, %{name: name})
        refute changeset.valid?, "Expected #{name} to be invalid"
        assert {:name, _} = hd(changeset.errors), "Expected error on :name for #{name}"
      end
    end
  end
end
