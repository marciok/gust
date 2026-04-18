defmodule Gust.DAG.Parser.Adapters.Elixir do
  @moduledoc false

  alias Gust.DAG.Definition
  alias Gust.DAG.Graph
  @behaviour Gust.DAG.Parser.Adapter

  @impl true
  def extension, do: ".ex"

  @impl true
  def parse_file(file_path) do
    parse_ex_file(file_path)
  end

  defp compile(file) do
    code_result =
      Code.with_diagnostics(fn ->
        try do
          [{mod, _bin}] = Code.compile_file(file)
          opts = options!(mod)
          tasks = list_tasks!(mod)

          {:ok, mod, opts, tasks}
        rescue
          err -> {:error, err}
        end
      end)

    case code_result do
      {{:ok, dag_module, opts, tasks}, warnings} ->
        {:ok, {dag_module, opts, tasks}, warnings}

      {{:error, error_type}, errors} ->
        {:error, error_type, errors}
    end
  end

  defp use_dsl?(ast) do
    Macro.prewalker(ast)
    |> Enum.filter(fn
      {:use, _meta, [{:__aliases__, _, [:Gust, :DSL]} | _config]} ->
        true

      _node ->
        false
    end)
    |> length() > 0
  end

  defp parse_ex_file(file_path) do
    with {:ok, ast} <- quote_content(file_path), true <- use_dsl?(ast) do
      define_dag(file_path)
    else
      false ->
        error = {[], "use Gust.DSL not found", ""}
        {:error, error}

      {:error, erros} ->
        {:error, erros}
    end
  end

  defp quote_content(path) do
    content = File.read!(path)
    Code.string_to_quoted(content)
  end

  defp define_dag(file_path) do
    name = Path.basename(file_path, extension())
    dag_def = default_dag_def(name, file_path)

    dag_def =
      case compile(file_path) do
        {:error, error, messages} ->
          %{dag_def | error: error, messages: messages}

        {:ok, {mod, opts, all_tasks}, warnings} ->
          task_list = build_task_list(mod)

          tasks = Graph.link_tasks(all_tasks) |> put_store_result(all_tasks)

          stages = build_stages(mod)

          :code.purge(mod)
          :code.delete(mod)

          %{
            dag_def
            | mod: mod,
              messages: warnings,
              tasks: tasks,
              task_list: task_list,
              options: opts,
              stages: stages
          }
      end

    {:ok, dag_def}
  end

  defp default_dag_def(name, file_path) do
    %Definition{name: name, file_path: file_path}
  end

  defp put_store_result(tasks, all_tasks) do
    for {t_name, opts} <- tasks, into: %{} do
      {t_name, Map.put(opts, :store_result, all_tasks[String.to_atom(t_name)][:store_result])}
    end
  end

  defp build_stages(mod) do
    list_tasks!(mod)
    |> Graph.link_tasks()
    |> Graph.to_stages()
    |> then(fn {:ok, stages} -> stages end)
  end

  defp build_task_list(mod) do
    build_stages(mod)
    |> List.flatten()
  end

  defp options!(mod) do
    opts = mod.__dag_options__()
    Keyword.validate!(opts, [:schedule, :on_finished_callback])
  end

  defp list_tasks!(mod) do
    mod.__dag_tasks__()
    |> Enum.map(fn {task_name, opts} ->
      {task_name, Keyword.put_new(opts, :store_result, false)}
    end)
  end
end
