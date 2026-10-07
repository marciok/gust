defmodule Gust.DAG.FolderTest do
  use ExUnit.Case, async: true

  import Gust.FSHelpers

  alias Gust.DAG.Folder

  setup do
    folder = make_rand_dir!("dags")
    on_exit(fn -> File.rm_rf!(folder) end)
    %{folder: folder}
  end

  test "accepts an existing DAG folder outside test", %{folder: folder} do
    assert :ok = Folder.verify!("prod", folder)
  end

  test "raises when the DAG folder does not exist outside test" do
    folder = missing_folder()

    assert_raise RuntimeError, "DAG folder does not exist!: #{folder}", fn ->
      Folder.verify!("prod", folder)
    end
  end

  test "does not verify the DAG folder in test" do
    assert :ok = Folder.verify!("test", missing_folder())
  end

  test "loads matching files from a folder path", %{folder: folder} do
    File.write!(Path.join(folder, "second.ex"), "")
    File.write!(Path.join(folder, "ignored.py"), "")
    File.write!(Path.join(folder, "first.ex"), "")

    expected = [Path.join(folder, "first.ex"), Path.join(folder, "second.ex")]
    actual = Gust.DAG.Parser.File.parse_folder(folder, wildcard: "*.ex")

    assert actual == expected
  end

  test "loads nested files recursively when wildcard matches nested paths", %{folder: folder} do
    nested = Path.join(folder, "nested")
    File.mkdir_p!(nested)
    File.write!(Path.join(folder, "first.ex"), "")
    File.write!(Path.join(nested, "second.ex"), "")
    File.write!(Path.join(nested, "third.py"), "")

    expected = [Path.join(folder, "first.ex"), Path.join(nested, "second.ex")]
    actual = Gust.DAG.Parser.File.parse_folder(folder, wildcard: "**/*.ex")

    assert actual == expected
  end

  test "extracts the DAG name from a path" do
    assert "some_dag" = Folder.dag_name("/tmp/dags/some_dag.ex")
  end

  test "returns reload for an existing file and removed for a missing file", %{folder: folder} do
    existing_file = Path.join(folder, "some_dag.ex")
    File.write!(existing_file, "")

    assert "reload" = Folder.action(existing_file)
    assert "removed" = Folder.action(missing_folder())
  end

  defp missing_folder do
    Path.join(System.tmp_dir!(), "missing-dags-folder-#{System.unique_integer([:positive])}")
  end
end
