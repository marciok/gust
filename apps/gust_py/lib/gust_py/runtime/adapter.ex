defmodule GustPy.Runtime.Adapter do
  @behaviour Gust.DAG.Runtime.Adapter

  alias Gust.DAG.Definition

  @impl true
  def setup(%Definition{file_path: file_path} = dag_def, runtime_id) do
    tmp_path = tmp_copy_path(file_path, runtime_id)
    File.cp!(file_path, tmp_path)

    %{dag_def | file_path: tmp_path}
  end

  @impl true
  def teardown(%Definition{file_path: file_path}, _runtime_id) do
    File.rm!(file_path)
    :ok
  end

  defp tmp_copy_path(file_path, runtime_id) do
    tmp_dir = System.tmp_dir!()
    base = Path.basename(file_path)

    Path.join(tmp_dir, "gust_py_dag_#{runtime_id}_#{base}")
  end
end
