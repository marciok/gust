defmodule Gust.DAG.Parser.File do
  @moduledoc false

  @behaviour Gust.DAG.Parser
  alias Gust.DAG.{Adapter, Folder}

  @impl true
  def parse_folder(path, opts \\ []) do
    if Keyword.has_key?(opts, :wildcard) do
      load_from_path(path, opts)
    else
      parser_modules = Keyword.get(opts, :parser_modules, Adapter.parser_modules())

      adapter_by_extension =
        Keyword.get(opts, :adapter_by_extension, Adapter.parser_extension_map())

      parser_extensions = Map.keys(adapter_by_extension) |> MapSet.new()

      path
      |> load_from_path(
        opts
        |> Keyword.put(:parser_modules, parser_modules)
        |> Keyword.put(:adapter_by_extension, adapter_by_extension)
        |> Keyword.put(:parser_extensions, parser_extensions)
      )
      |> Enum.map(&parse_file_result(&1, adapter_by_extension))
      |> Enum.reject(&is_nil/1)
    end
  end

  def load_from_path(path, opts \\ []) do
    if is_binary(path) do
      parser_modules = Keyword.get(opts, :parser_modules, Adapter.parser_modules())

      parser_extensions =
        Keyword.get(opts, :parser_extensions) ||
          Enum.flat_map(parser_modules, & &1.extensions()) |> MapSet.new()

      wildcard = Keyword.get(opts, :wildcard, "**/*")

      path
      |> Path.join(normalize_wildcard(wildcard))
      |> Path.wildcard()
      |> Enum.filter(fn filename ->
        Path.extname(filename) in parser_extensions
      end)
      |> Enum.sort()
    else
      []
    end
  end

  def adapter_for_extension(extension) do
    Adapter.parser_for_extension(extension)
  end

  defp parse_file_result(filename, adapter_by_extension) do
    case Map.get(adapter_by_extension, Path.extname(filename)) do
      nil -> nil
      parser_module -> {Folder.dag_name(filename), parse(parser_module, filename)}
    end
  end

  defp normalize_wildcard(wildcard) when is_binary(wildcard) do
    wildcard
    |> String.trim_leading("/")
    |> String.trim_leading("\\")
  end

  defp normalize_wildcard(_), do: "**/*"

  @impl true
  def parse(adapter, file_path) do
    if File.exists?(file_path) do
      adapter.parse_file(file_path)
    else
      {:error, :enoent}
    end
  end
end
