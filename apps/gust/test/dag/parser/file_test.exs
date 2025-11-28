defmodule DAG.Parser.FileTest do
  use Gust.DataCase, async: false
  import Gust.FSHelpers
  alias Gust.DAG.Parser.File, as: Parser

  setup do
    dir = make_rand_dir!("dags")

    on_exit(fn ->
      File.rm_rf!(dir)
    end)

    {:ok, tmp_dir: dir}
  end

  describe "parser_folder/1" do
    test "parse each ex file", %{tmp_dir: dags_folder} do
      content = """
        defmodule MyValidDag do
          use Gust.DSL, schedule: "* * * * *"
        end
      """

      File.write!("#{dags_folder}/another_file.txt", "")
      dag_name = "my_name"
      file = "#{dags_folder}/#{dag_name}.ex"
      File.write!(file, content)

      assert [{^dag_name, {:ok, _dag_def}}] = Parser.parse_folder(dags_folder)
    end
  end

  describe "parse/1" do
    test "file does exists" do
      file = "ghost_file.ex"

      assert {:error, :enoent} = Parser.parse(file)
    end

    test "file is not valid", %{tmp_dir: dags_folder} do
      dag_definition = """
        defmodule MyValidDag do
          use Gust.DSL, schedule: "* * * * *"
          |>
        end
      """

      dag_name = "my_name"
      file = "#{dags_folder}/#{dag_name}.ex"
      File.write!(file, dag_definition)

      assert {:error,
              {
                [{:line, 4}, {:column, 3}],
                "syntax error before: ",
                "'end'"
              }} = Parser.parse(file)
    end

    test "file is not including DSL not valid dag", %{tmp_dir: dags_folder} do
      dag_definition = """
        defmodule MyValidDag do
        end
      """

      dag_name = "my_name"
      file = "#{dags_folder}/#{dag_name}.ex"
      File.write!(file, dag_definition)

      assert {:error, {[], "use Gust.DSL not found", ""}} = Parser.parse(file)
    end

    test "file is valid dag", %{tmp_dir: dags_folder} do
      dag_definition = """
        defmodule MyValidDagEmpty do
          use Gust.DSL, schedule: "* * * * *"

          def dup, do: :ok
          def dup, do: :error

          task :bye do
            # saying bye
          end

          task :hi, downstream: [:bye], store_result: true do
            # saying hi
          end
        end
      """

      dag_name = "my_name"
      file = "#{dags_folder}/#{dag_name}.ex"
      File.write!(file, dag_definition)

      warning_message =
        "this clause for dup/0 cannot match because a previous clause at line 4 always matches"

      warnigs = [
        %{
          message: warning_message,
          position: {5, 9},
          file: file,
          stacktrace: [],
          source: file,
          span: nil,
          severity: :warning
        }
      ]

      dag_def = %Gust.DAG.Definition{
        name: dag_name,
        mod: MyValidDagEmpty,
        task_list: ["hi", "bye"],
        stages: [["hi"], ["bye"]],
        options: [{:schedule, "* * * * *"}],
        messages: warnigs,
        file_path: file,
        error: %{},
        tasks: %{
          "bye" => %{
            upstream: MapSet.new(["hi"]),
            downstream: MapSet.new([]),
            store_result: nil
          },
          "hi" => %{
            upstream: MapSet.new([]),
            downstream: MapSet.new(["bye"]),
            store_result: true
          }
        }
      }

      assert {:ok, ^dag_def} = Parser.parse(file)
    end

    test "file has code errors", %{tmp_dir: dags_folder} do
      dag_definition = """
        defmodule MyValidDag do
          use Gust.DSL

          kaboomm
        end
      """

      dag_name = "my_name"
      file = "#{dags_folder}/#{dag_name}.ex"
      File.write!(file, dag_definition)

      {:ok, dag_def} = Parser.parse(file)
      [error_message] = dag_def.messages
      assert "undefined variable \"kaboomm\"" == error_message.message

      assert "cannot compile module MyValidDag (errors have been logged)" ==
               dag_def.error.description
    end
  end

  describe "maybe_ex_file/1" do
    test "file not endining with ex", %{tmp_dir: dir} do
      file_path = "#{dir}/test_file.txt"
      File.write!(file_path, "")

      assert is_nil(Parser.maybe_ex_file(file_path))
    end

    test "file endining with ex", %{tmp_dir: dir} do
      file_path = "#{dir}/test_file.ex"
      File.write!(file_path, "")

      assert file_path == Parser.maybe_ex_file(file_path)
    end
  end
end
