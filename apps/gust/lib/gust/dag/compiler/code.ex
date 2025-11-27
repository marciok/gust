defmodule Gust.DAG.Compiler.Code do
  @moduledoc false
  @behaviour Gust.DAG.Compiler

  def compile(dag_def) do
    {:ok, ast} = Code.string_to_quoted(File.read!(dag_def.file_path))

    runtime_mod = Module.concat(["Gust", "Runner", "#{dag_def.mod}_#{random_udid()}"])
    dag_ast = patch_module(ast, runtime_mod)

    {dag_module, _} = Code.compile_quoted(dag_ast) |> List.first()
    dag_module
  end

  def purge(mod) do
    :code.purge(mod)
    :code.delete(mod)
  end

  defp random_udid do
    timestamp = :os.system_time(:microsecond)
    random = :crypto.strong_rand_bytes(4) |> Base.encode16()
    "#{timestamp}-#{random}"
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
