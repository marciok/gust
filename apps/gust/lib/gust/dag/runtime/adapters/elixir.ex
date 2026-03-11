defmodule Gust.DAG.Runtime.Adapters.Elixir do
  @moduledoc false

  @behaviour Gust.DAG.Runtime.Adapter

  alias Gust.DAG.Definition

  @impl true
  def setup(%Definition{} = dag_def, runtime_id) do
    runtime_mod = compile(dag_def, runtime_id)
    %{dag_def | mod: runtime_mod}
  end

  @impl true
  def teardown(%Definition{mod: mod}, _runtime_id) do
    purge(mod)
    :ok
  end

  @impl true
  def on_finished_callback(%Definition{mod: mod}, fn_name, run, status) do
    apply(mod, fn_name, [status, run])
    :ok
  end

  @impl true
  def kill(task_pid) do
    true = Process.exit(task_pid, :kill)
  end

  defp compile(%Definition{file_path: file_path} = dag_def, runtime_id) do
    {:ok, ast} = Code.string_to_quoted(File.read!(file_path))

    runtime_mod = Module.concat(["Gust", "Runner", "#{dag_def.mod}_#{runtime_id}"])
    dag_ast = patch_module(ast, runtime_mod)

    {dag_module, _} = Code.compile_quoted(dag_ast, file_path) |> List.first()
    dag_module
  end

  defp purge(mod) do
    :code.purge(mod)
    :code.delete(mod)
  end

  defp patch_module(ast, runtime_mod) do
    Macro.postwalk(ast, fn
      {:defmodule, meta, [_module_ast_node, block]} ->
        {:defmodule, meta, [Module.concat([runtime_mod]), block]}

      node ->
        node
    end)
  end
end
