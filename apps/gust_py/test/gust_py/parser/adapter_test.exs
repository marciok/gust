defmodule GustPy.Parser.AdapterTest do
  use ExUnit.Case, async: false
  import Mox
  alias Gust.DAG.Definition
  alias GustPy.Parser.Adapter

  @file_path "/dags/enya.py"

  @valid_dag [
    %{
      "name" => "",
      "mod" => "Enya",
      "error" => %{},
      "messages" => [],
      "task_list" => ["hello", "world", "olam", "bye"],
      "stages" => [],
      "tasks" => %{
        "hello" => %{"deps" => ["world", "olam"], "save" => true},
        "world" => %{"deps" => ["bye"], "save" => false},
        "olam" => %{"deps" => ["bye"], "save" => false},
        "bye" => %{"deps" => [], "save" => false}
      },
      "file_path" => @file_path,
      "options" => %{"schedule" => nil}
    }
  ]

  @invalid_dag [
    %{
      "name" => "",
      "mod" => "",
      "error" => %{
        "file" => @file_path,
        "line" => 9,
        "description" => "expected an indented block after function definition on line 8"
      },
      "messages" => ["expected an indented block after function definition on line 8"],
      "task_list" => [],
      "stages" => [],
      "tasks" => %{},
      "file_path" => @file_path,
      "options" => %{"schedule" => nil}
    }
  ]

  setup :verify_on_exit!
  setup :set_mox_from_context

  setup do
    previous_executor = Application.get_env(:gust_py, :executor)
    Application.put_env(:gust_py, :executor, GustPy.ExecutorMock)

    on_exit(fn ->
      restore_app_env(:gust_py, :executor, previous_executor)
    end)

    :ok
  end

  describe "extension/0" do
    test "returns .py" do
      assert ".py" == Adapter.extension()
    end
  end

  describe "parse_file/1" do
    test "returns a parsed dag definition from executor output" do
      GustPy.ExecutorMock
      |> expect(:parse_dag, fn @file_path ->
        {Jason.encode!(@valid_dag), 0}
      end)

      assert {:ok, %Definition{} = dag_def} = Adapter.parse_file(@file_path)

      assert dag_def.name == "enya"
      assert dag_def.mod == "Enya"
      assert dag_def.adapter == :python
      assert dag_def.file_path == @file_path
      assert dag_def.options == [schedule: nil]
      assert dag_def.messages == []
      assert dag_def.error == %{}

      assert MapSet.new(Map.keys(dag_def.tasks)) ==
               MapSet.new(["hello", "world", "olam", "bye"])

      assert MapSet.new(dag_def.task_list) ==
               MapSet.new(["hello", "world", "olam", "bye"])

      assert Enum.map(dag_def.stages, &MapSet.new/1) == [
               MapSet.new(["hello"]),
               MapSet.new(["world", "olam"]),
               MapSet.new(["bye"])
             ]

      assert MapSet.equal?(
               dag_def.tasks["hello"].downstream,
               MapSet.new(["world", "olam"])
             )

      assert MapSet.equal?(dag_def.tasks["hello"].upstream, MapSet.new())
      assert dag_def.tasks["hello"].store_result == true

      assert MapSet.equal?(dag_def.tasks["world"].upstream, MapSet.new(["hello"]))
      assert MapSet.equal?(dag_def.tasks["olam"].upstream, MapSet.new(["hello"]))

      assert MapSet.equal?(
               dag_def.tasks["bye"].upstream,
               MapSet.new(["world", "olam"])
             )

      assert dag_def.tasks["world"].store_result == false
      assert dag_def.tasks["olam"].store_result == false
      assert dag_def.tasks["bye"].store_result == false
    end

    test "returns parsing error when executor reports a parse error" do
      GustPy.ExecutorMock
      |> expect(:parse_dag, fn @file_path ->
        {Jason.encode!(@invalid_dag), 0}
      end)

      assert {:error,
              {[line: 9], "parsing error",
               "expected an indented block after function definition on line 8"}} =
               Adapter.parse_file(@file_path)
    end

    test "returns error when executor exits with non-zero status" do
      GustPy.ExecutorMock
      |> expect(:parse_dag, fn @file_path ->
        {"", 1}
      end)

      assert {:error, {[line: ""], "Parse file command failed, exit: 1", ""}} =
               Adapter.parse_file(@file_path)
    end
  end

  defp restore_app_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_app_env(app, key, value), do: Application.put_env(app, key, value)
end
