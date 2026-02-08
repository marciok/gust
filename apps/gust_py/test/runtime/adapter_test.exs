defmodule GustPy.Runtime.AdapterTest do
  use ExUnit.Case, async: true

  alias Gust.DAG.Definition
  alias GustPy.Runtime.Adapter

  test "setup copies the dag file to a temp location and teardown removes it" do
    tmp_dir = System.tmp_dir!()
    original_path = Path.join(tmp_dir, "gust_py_adapter_test.ex")
    File.write!(original_path, "dag content")

    on_exit(fn -> File.rm(original_path) end)

    dag_def = %Definition{file_path: original_path}

    updated_def = Adapter.setup(dag_def, "runtime-id")

    assert updated_def.file_path != original_path
    assert File.exists?(updated_def.file_path)
    assert File.read!(updated_def.file_path) == "dag content"

    assert :ok = Adapter.teardown(updated_def, "runtime-id")
    refute File.exists?(updated_def.file_path)
    assert File.exists?(original_path)
  end
end
