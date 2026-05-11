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
    assert dfn.adapter == :elixir

    assert Map.keys(dfn) |> Enum.sort() ==
             [
               :__struct__,
               :adapter,
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

  test "to_json/1 normalizes nested mapsets and keyword options" do
    dag_def = %Definition{
      name: "marcio",
      options: [schedule: "@daily"],
      stages: [MapSet.new(["second_task", "first_task"])],
      tasks: %{
        "first_task" => %{
          upstream: MapSet.new(),
          downstream: MapSet.new(["say_bye"])
        },
        "say_bye" => %{
          upstream: MapSet.new(["first_task"]),
          downstream: MapSet.new()
        }
      }
    }

    assert {:ok, json} = Definition.to_json(dag_def)

    assert %{
             "name" => "marcio",
             "options" => %{"schedule" => "@daily"},
             "stages" => [["first_task", "second_task"]],
             "tasks" => %{
               "first_task" => %{
                 "upstream" => [],
                 "downstream" => ["say_bye"]
               },
               "say_bye" => %{
                 "upstream" => ["first_task"],
                 "downstream" => []
               }
             }
           } = Jason.decode!(json)
  end
end
