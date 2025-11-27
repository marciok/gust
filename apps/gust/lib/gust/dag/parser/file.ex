defmodule Gust.DAG.Parser.File do
  @moduledoc false

  @behaviour Gust.DAG.Parser

  alias Gust.DAG.Definition
  alias Gust.DAG.Graph

  @impl true
  def parse_folder(folder) do
    ex_files(folder)
    |> Enum.map(&"#{Path.absname(folder)}/#{&1}")
    |> Enum.map(fn path ->
      name = Path.basename(path, ".ex")
      {name, parse(path)}
    end)
  end

  @impl true
  def parse(file_path) do
    if File.exists?(file_path) do
      parse_file(file_path)
    else
      {:error, :enoent}
    end
  end

  defp parse_file(file_path) do
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
    name = Path.basename(file_path, ".ex")
    dag_def = default_dag_def(name, file_path)

    dag_def =
      case compile(file_path) do
        {:error, error, messages} ->
          %{dag_def | error: error, messages: messages}

        {:ok, mod} ->
          task_list = build_task_list(mod)
          all_tasks = list_tasks(mod)

          tasks = Graph.link_tasks(all_tasks) |> put_store_result(all_tasks)

          options = options(mod)
          stages = build_stages(mod)

          :code.purge(mod)
          :code.delete(mod)

          %{
            dag_def
            | mod: mod,
              tasks: tasks,
              task_list: task_list,
              options: options,
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
    list_tasks(mod)
    |> Graph.link_tasks()
    |> Graph.to_stages()
    |> then(fn {:ok, stages} -> stages end)
  end

  defp build_task_list(mod) do
    build_stages(mod)
    |> List.flatten()
  end

  defp options(mod) do
    # TODO: Validate schedule..
    mod.__dag_options__()
  end

  defp list_tasks(mod) do
    mod.__dag_tasks__()
  end

  @impl true
  def maybe_ex_file(path) do
    if Path.extname(path) == ".ex", do: path, else: nil
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

  defp compile(file) do
    code_result =
      Code.with_diagnostics(fn ->
        try do
          compiled = Code.compile_file(file) |> List.first()

          {:ok, compiled}
        rescue
          err -> {:error, err}
        end
      end)

    case code_result do
      {{:ok, {dag_module, _}}, _warnings} ->
        {:ok, dag_module}

      {{:error, error_type}, errors} ->
        {:error, error_type, errors}
    end
  end

  defp ex_files(folder) do
    folder
    |> File.ls!()
    |> Enum.filter(&maybe_ex_file(&1))
  end
end
