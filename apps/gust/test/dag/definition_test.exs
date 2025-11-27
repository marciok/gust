defmodule DAG.DefinitionTest do
  alias Gust.DAG.Definition
  use Gust.DataCase

  test "fields are present" do
    dfn = %Definition{}
    assert dfn.name == ""
    assert dfn.mod == nil
    assert dfn.task_list == []
    assert dfn.stages == []
    assert dfn.tasks == %{}
    assert dfn.error == %{}
    assert dfn.messages == []
    assert dfn.file_path == ""
    assert dfn.options == []

    assert Map.keys(dfn) |> Enum.sort() ==
             [
               :__struct__,
               :error,
               :file_path,
               :messages,
               :mod,
               :name,
               :options,
               :stages,
               :task_list,
               :tasks
             ]
  end
end
