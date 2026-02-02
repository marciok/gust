defmodule DAG.Parser.FileTest do
  use Gust.DataCase, async: false
  import Gust.FSHelpers
  import Mox
  alias Gust.DAG.Parser.File, as: Parser

  setup :verify_on_exit!
  setup :set_mox_from_context

  setup do
    dir = make_rand_dir!("dags")
    previous_adapters = Application.get_env(:gust, :dag_adapter, [])

    on_exit(fn ->
      File.rm_rf!(dir)
      Application.put_env(:gust, :dag_adapter, previous_adapters)
    end)

    {:ok, tmp_dir: dir}
  end

  describe "parser_folder/1" do
    test "parses files for configured adapters", %{tmp_dir: dags_folder} do
      Application.put_env(:gust, :dag_adapter,
        elixir: %{
          parser: Gust.DAGParserAdapterMock,
          runtime: Gust.DAG.Runtime.Adapters.Elixir,
          task_worker: Gust.DAG.TaskWorker.Adapters.Elixir
        }
      )

      first_path = "#{dags_folder}/first.mock"
      second_path = "#{dags_folder}/second.mock"
      File.write!(first_path, "")
      File.write!(second_path, "")

      Gust.DAGParserAdapterMock
      |> expect(:list_files, fn ^dags_folder -> ["first.mock", "second.mock"] end)
      |> expect(:extension, 2, fn -> ".mock" end)
      |> expect(:parse_file, fn ^first_path -> {:ok, :first_parsed} end)
      |> expect(:parse_file, fn ^second_path -> {:ok, :second_parsed} end)

      assert [
               {"first", {:ok, :first_parsed}},
               {"second", {:ok, :second_parsed}}
             ] == Parser.parse_folder(dags_folder)
    end
  end

  describe "parse/2" do
    test "file does exists" do
      file = "ghost_file.ex"

      assert {:error, :enoent} = Parser.parse(Gust.DAGParserAdapterMock, file)
    end

    test "delegates to adapter when file exists", %{tmp_dir: dags_folder} do
      file = "#{dags_folder}/some_file.ex"
      File.write!(file, "")

      Gust.DAGParserAdapterMock
      |> expect(:parse_file, fn ^file -> {:ok, :parsed} end)

      assert {:ok, :parsed} = Parser.parse(Gust.DAGParserAdapterMock, file)
    end
  end
end
