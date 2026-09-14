defmodule Gust.DAG.Adapter do
  @moduledoc """
  Provides functions to manage and interact with DAG adapters.
  Handles loading, caching, and retrieving adapter configurations,
  parser modules, and extension mappings.
  """

  @adapter_cache_key {__MODULE__, :adapter_cache}

  @default_adapters [
    elixir: %{
      parser: Gust.DAG.Parser.Adapters.Elixir,
      runtime: Gust.DAG.Runtime.Adapters.Elixir,
      task_worker: Gust.DAG.TaskWorker.Adapters.Elixir
    }
  ]

  @doc """
  Forced reload of the DAG adapter configuration and update of persistent cache.
  Returns the updated cache containing adapters, extension map, and config hash.
  """
  def reload do
    Gust.PersistentTermCache.reload(@adapter_cache_key, &reload_cache/0)
  end

  @doc """
  Retrieves the implementation module for the given adapter and key.
  Raises an error if the adapter or key is not found.
  """
  def impl!(adapter_name, key) do
    adapter_name
    |> adapter_config!()
    |> Map.fetch!(key)
  end

  @doc """
  Retrieves the parser module for the given adapter name.
  Raises an error if the adapter or parser is not found.
  """
  def parser_module!(adapter_name) do
    impl!(adapter_name, :parser)
  end

  @doc """
  Retrieves a list of all unique parser modules from the configured adapters.
  """
  def parser_modules, do: fetch_or_reload().parser_modules

  @doc """
  Retrieves the parser module associated with the given file extension.
  Returns `nil` if no parser is found for the extension.
  """
  def parser_for_extension(extension) do
    extension_map() |> Map.get(extension)
  end

  @doc false
  def parser_extension_map, do: extension_map()

  defp adapter_config!(adapter_name) do
    adapters() |> Keyword.fetch!(adapter_name)
  end

  defp adapters, do: fetch_or_reload().adapters

  defp extension_map, do: fetch_or_reload().extension_map

  defp fetch_or_reload do
    Gust.PersistentTermCache.fetch_or_reload(
      @adapter_cache_key,
      &reload_cache/0,
      &cache_valid?/2
    )
  end

  defp reload_cache do
    configured = Application.get_env(:gust, :dag_adapter, [])
    config_hash = hash_config(configured)

    adapters =
      Keyword.merge(@default_adapters, configured, fn _key, default_val, configured_val ->
        Map.merge(default_val, configured_val)
      end)

    parser_modules =
      adapters
      |> Keyword.values()
      |> Enum.map(&Map.fetch!(&1, :parser))
      |> Enum.uniq()

    extension_map = build_extension_map(parser_modules)

    cache = %{adapters: adapters, extension_map: extension_map, parser_modules: parser_modules}

    {cache, config_hash}
  end

  defp cache_valid?(_cache, hash), do: hash == hash_config()

  defp hash_config(config \\ Application.get_env(:gust, :dag_adapter, [])) do
    config
    |> :erlang.term_to_binary()
    |> :erlang.phash2()
  end

  defp build_extension_map(parser_modules) do
    parser_modules
    |> Enum.flat_map(fn parser ->
      if is_atom(parser) and Code.ensure_loaded?(parser) and
           function_exported?(parser, :extensions, 0) do
        Enum.map(parser.extensions(), &{&1, parser})
      else
        []
      end
    end)
    |> Map.new()
  end
end
