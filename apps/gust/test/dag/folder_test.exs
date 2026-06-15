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

  test "lists sorted files matching the extension", %{folder: folder} do
    File.write!(Path.join(folder, "second.ex"), "")
    File.write!(Path.join(folder, "ignored.py"), "")
    File.write!(Path.join(folder, "first.ex"), "")

    assert ["first.ex", "second.ex"] = Folder.list_files(folder, ".ex")
  end

  test "builds an absolute file path", %{folder: folder} do
    assert Path.join(Path.absname(folder), "some_dag.ex") ==
             Folder.absolute_path(folder, "some_dag.ex")
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
