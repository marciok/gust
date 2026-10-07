defmodule GustPy.Runtime.Adapter do
  @moduledoc false

  @behaviour Gust.DAG.Runtime.Adapter

  alias Gust.DAG.Definition

  @impl true
  def kill(task_pid) do
    GenServer.cast(task_pid, {:kill})
  end

  @impl true
  def setup(%Definition{} = dag_def, runtime_id) do
    tmp_path = tmp_copy_path(dag_def.file_path, runtime_id)
    write_runtime_source!(dag_def, tmp_path)

    %{dag_def | file_path: tmp_path}
  end

  @impl true
  def on_finished_callback(%Definition{file_path: file, name: name}, fn_name, run, status) do
    args = [
      "run",
      "done",
      "--file",
      file,
      "--dag",
      name,
      "--fn-name",
      fn_name,
      "--status",
      Atom.to_string(status),
      "--run-id",
      Integer.to_string(run.id)
    ]

    GustPy.Executor.run(args)
  end

  @impl true
  def teardown(%Definition{file_path: file_path}, _runtime_id) do
    File.rm!(file_path)
  end

  defp tmp_copy_path(file_path, runtime_id) do
    tmp_dir = System.tmp_dir!()
    base = Path.basename(file_path)

    Path.join(tmp_dir, "gust_py_dag_#{runtime_id}_#{base}")
  end

  defp write_runtime_source!(%Definition{source: source}, tmp_path) when is_binary(source) do
    File.write!(tmp_path, source)
  end

  defp write_runtime_source!(%Definition{file_path: file_path}, tmp_path) do
    File.cp!(file_path, tmp_path)
  end
end
