defmodule GustPy.Runtime.AdapterTest do
  use Gust.DataCase
  import Gust.FlowsFixtures

  alias Gust.DAG.Definition
  alias GustPy.Runtime.Adapter

  import Mox

  setup :verify_on_exit!
  setup :set_mox_from_context

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

  test "on_finished_callback invoke callback via executor" do
    fn_name = "done_here"
    name = "callback_dag"
    file_path = "./some/path"
    dag_def = %Definition{file_path: file_path, name: name}
    dag = dag_fixture(%{name: name})
    run = run_fixture(%{dag_id: dag.id})
    status = :succeeded

    args_list = [
      "run",
      "done",
      "--file",
      file_path,
      "--dag",
      name,
      "--fn-name",
      fn_name,
      "--status",
      Atom.to_string(status),
      "--run-id",
      Integer.to_string(run.id)
    ]

    GustPy.ExecutorMock
    |> expect(:run, fn ^args_list ->
      :ok
    end)

    Adapter.on_finished_callback(dag_def, fn_name, run, status)
  end
end
