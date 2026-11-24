defmodule DAG.Parser.Adapters.ElixirTest do
  use Gust.DataCase, async: false
  import Gust.FSHelpers
  alias Gust.DAG.Parser.Adapters.Elixir, as: Adapter

  setup do
    dir = make_rand_dir!("dags")

    on_exit(fn ->
      File.rm_rf!(dir)
    end)

    {:ok, tmp_dir: dir}
  end

  describe "extension/0" do
    test "returns .ex" do
      assert ".ex" == Adapter.extension()
    end
  end

  describe "parse_file/1" do
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
              }} = Adapter.parse_file(file)
    end

    test "file is not including DSL not valid dag", %{tmp_dir: dags_folder} do
      dag_definition = """
        defmodule MyValidDag do
        end
      """

      dag_name = "my_name"
      file = "#{dags_folder}/#{dag_name}.ex"
      File.write!(file, dag_definition)

      assert {:error, {[], "use Gust.DSL not found", ""}} = Adapter.parse_file(file)
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

      warnings = [
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
        messages: warnings,
        file_path: file,
        error: %{},
        tasks: %{
          "bye" => %{
            upstream: MapSet.new(["hi"]),
            downstream: MapSet.new([]),
            store_result: false,
            skip_if: nil,
            map_over: nil,
            wait_for: nil
          },
          "hi" => %{
            upstream: MapSet.new([]),
            downstream: MapSet.new(["bye"]),
            store_result: true,
            skip_if: nil,
            map_over: nil,
            wait_for: nil
          }
        }
      }

      assert {:ok, ^dag_def} = Adapter.parse_file(file)
    end

    test "file has code errors", %{tmp_dir: dags_folder} do
      dag_definition = """
        defmodule CompiledErroredDag do
          use Gust.DSL

          kaboomm
        end
      """

      dag_name = "my_name"
      file = "#{dags_folder}/#{dag_name}.ex"
      File.write!(file, dag_definition)

      {:ok, dag_def} = Adapter.parse_file(file)
      [error_message] = dag_def.messages
      assert "undefined variable \"kaboomm\"" == error_message.message

      assert "cannot compile module CompiledErroredDag (errors have been logged)" ==
               dag_def.error.description
    end

    test "file has unknown task options", %{tmp_dir: dags_folder} do
      dag_definition = """
        defmodule MyInvalidTaskDag do
          use Gust.DSL, schedule: "* * * * *"

          task :bye, foo_bar: "hi" do
            # saying bye
          end

        end
      """

      dag_name = "my_name"
      file = "#{dags_folder}/#{dag_name}.ex"
      File.write!(file, dag_definition)

      {:ok, dag_def} = Adapter.parse_file(file)
      [error_message] = dag_def.messages

      assert "unknown keys [:foo_bar] in [foo_bar: \"hi\"], the allowed keys are: [:downstream, :store_result, :ctx, :skip_if, :map_over, :wait_for]" ==
               error_message.message

      assert "cannot compile module MyInvalidTaskDag (errors have been logged)" ==
               dag_def.error.description
    end

    test "file has unknown dag options", %{tmp_dir: dags_folder} do
      dag_definition = """
        defmodule MyValidDag do
          use Gust.DSL, foo_bar: "hi", schedule: "* * * * *"

        end
      """

      dag_name = "my_name"
      file = "#{dags_folder}/#{dag_name}.ex"
      File.write!(file, dag_definition)

      {:ok, dag_def} = Adapter.parse_file(file)

      assert %CompileError{description: "invalid DAG options: " <> message} = dag_def.error

      assert message ==
               "unknown keys [:foo_bar] in [foo_bar: \"hi\", schedule: \"* * * * *\"], the allowed keys are: [:schedule, :on_finished_callback, :runs]"
    end

    test "file has runs retention", %{tmp_dir: dags_folder} do
      replace_env(:run_pruner, schedule: "@daily")

      file =
        write_dag!(dags_folder, """
          defmodule MyRetentionDag do
            use Gust.DSL, runs: [retention: [max_count: 5_000]]

            task :bye do
            end
          end
        """)

      {:ok, dag_def} = Adapter.parse_file(file)

      assert dag_def.error == %{}
      assert dag_def.messages == []
      assert dag_def.options == [runs: [retention: [max_count: 5_000]]]
    end

    test "file has runs retention without a pruner schedule", %{tmp_dir: dags_folder} do
      replace_env(:run_pruner, [])

      file =
        write_dag!(dags_folder, """
          defmodule MyUnprunedRetentionDag do
            use Gust.DSL, runs: [retention: [max_count: 5_000]]

            task :bye do
            end
          end
        """)

      {:ok, dag_def} = Adapter.parse_file(file)

      assert dag_def.error == %{}
      assert [%{severity: :warning, message: message, file: ^file}] = dag_def.messages
      assert message =~ "pruning is off"
    end

    test "file has unknown runs keys", %{tmp_dir: dags_folder} do
      file =
        write_dag!(dags_folder, """
          defmodule MyUnknownRunsDag do
            use Gust.DSL, runs: [foo: true]
          end
        """)

      {:ok, dag_def} = Adapter.parse_file(file)

      assert %CompileError{description: "invalid DAG options: " <> message} = dag_def.error

      assert message ==
               "unknown keys [:foo] in runs [foo: true], the allowed keys are: [:retention, :concurrency]"
    end

    test "file has unknown runs retention keys", %{tmp_dir: dags_folder} do
      file =
        write_dag!(dags_folder, """
          defmodule MyUnknownRetentionDag do
            use Gust.DSL, runs: [retention: [max_age: 30]]
          end
        """)

      {:ok, dag_def} = Adapter.parse_file(file)

      assert %CompileError{description: "invalid DAG options: " <> message} = dag_def.error

      assert message ==
               "unknown keys [:max_age] in runs retention [max_age: 30], the allowed keys are: [:max_count]"
    end

    test "file has an invalid runs retention max_count", %{tmp_dir: dags_folder} do
      file =
        write_dag!(dags_folder, """
          defmodule MyInvalidMaxCountDag do
            use Gust.DSL, runs: [retention: [max_count: -1]]
          end
        """)

      {:ok, dag_def} = Adapter.parse_file(file)

      assert %CompileError{description: "invalid DAG options: " <> message} = dag_def.error
      assert message == "runs retention max_count must be a positive integer, got: -1"
    end

    test "file has an invalid schedule", %{tmp_dir: dags_folder} do
      file =
        write_dag!(dags_folder, """
          defmodule MyInvalidScheduleDag do
            use Gust.DSL, schedule: "bla"
          end
        """)

      {:ok, dag_def} = Adapter.parse_file(file)

      assert %CompileError{file: ^file, description: "invalid DAG options: " <> message} =
               dag_def.error

      assert message =~ "invalid schedule \"bla\""

      assert [%{severity: :error, message: "invalid DAG options: " <> ^message}] =
               dag_def.messages

      assert dag_def.options == []
      refute :code.is_loaded(MyInvalidScheduleDag)
    end
  end

  defp write_dag!(dags_folder, content) do
    file = "#{dags_folder}/my_name.ex"
    File.write!(file, content)
    file
  end
end
