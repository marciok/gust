defmodule Gust.DAG.Source.Config do
  @moduledoc """
  Resolves the configured DAG sources from `Application.get_env(:gust, :dag_sources)`.

  Every configured source must use the shape `{id, opts}` and include a required
  `:type` option, e.g. `{"git-main", type: "git", url: "https://..."}`.
  """
  require Logger

  @default_source {"default-folder", type: Gust.DAG.Source.Folder}
  @source_cache_key {__MODULE__, :dag_sources}
  @source_modules [
    Gust.DAG.Source.Database,
    Gust.DAG.Source.Folder,
    Gust.DAG.Source.Git,
    Gust.DAG.Source.GitWebhook,
    Gust.DAG.Source.S3
  ]

  @source_map @source_modules
              |> Enum.flat_map(fn module ->
                short_name = module |> Module.split() |> List.last()

                [
                  {String.downcase(short_name), module},
                  {Module.concat([short_name]), module}
                ]
              end)
              |> Enum.into(%{})

  @known_source_impls @source_map |> Map.values() |> MapSet.new()

  @doc """
  Reads the cached DAG source configurations, reloading them if necessary.
  """
  @spec read() :: [map()]
  def read do
    Gust.PersistentTermCache.fetch_or_reload(
      @source_cache_key,
      &reload_cache/0,
      &cache_valid?/2
    )
  end

  @spec reload() :: [map()]
  def reload do
    Gust.PersistentTermCache.reload(@source_cache_key, &reload_cache/0)
  end

  defp reload_cache do
    raw_config = source_config_from_env()
    config = normalize_source_term(raw_config)
    hash = hash_config(raw_config)
    {config, hash}
  end

  defp cache_valid?(_config, hash), do: hash == hash_config(source_config_from_env())

  defp source_config_from_env do
    Application.get_env(:gust, :dag_sources)
  end

  defp normalize_source_config(nil), do: []

  defp normalize_source_config(source_configs) when is_list(source_configs), do: source_configs

  defp normalize_source_config(module) when is_atom(module) or is_binary(module) do
    [legacy_source_map(module, %{})]
  end

  defp normalize_source_config({module, opts})
       when is_atom(module) or is_binary(module) do
    [legacy_source_map(module, ensure_config_map(opts))]
  end

  defp normalize_source_config(%{type: _} = source_map) do
    [legacy_map_source(source_map)]
  end

  defp normalize_source_config(%{"type" => _} = source_map) do
    [legacy_map_source(source_map)]
  end

  defp normalize_source_config(other) do
    raise ArgumentError,
          "Invalid DAG sources config: #{inspect(other)}. Expected a list of sources or a source-like value compatible with migration."
  end

  defp legacy_source_map(module, config_map) do
    config_map
    |> ensure_config_map()
    |> Map.put(:id, default_source_id(module))
    |> Map.put(:type, resolve_source_module(module))
  end

  defp legacy_map_source(source_map) do
    source_map
    |> ensure_config_map()
    |> Map.put(:id, default_source_id(Map.get(source_map, :type, Map.get(source_map, "type"))))
    |> Map.put(
      :type,
      resolve_source_module(Map.get(source_map, :type, Map.get(source_map, "type")))
    )
  end

  defp default_source_id(module) when is_atom(module) do
    module
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
    |> then(&"default-#{&1}")
  end

  defp default_source_id(module) when is_binary(module) do
    module
    |> String.trim()
    |> String.replace(~r/[^a-zA-Z0-9]+/, "-")
    |> String.downcase()
    |> then(&"default-#{&1}")
  end

  @spec cached_state() :: {[map()], non_neg_integer()}
  def cached_state do
    :persistent_term.get(@source_cache_key, {[], 0})
  end

  defp normalize_source_term(source_configs)
       when is_list(source_configs) do
    source_configs
    |> normalize_source_config()
    |> case do
      [] ->
        Logger.warning("No DAG source configurations found, using default folder source")
        [normalize_config(@default_source)]

      configs ->
        Enum.map(configs, &normalize_config/1)
    end
  end

  defp normalize_source_term(source_config) do
    source_config
    |> normalize_source_config()
    |> normalize_source_term()
  end

  defp hash_config(config) do
    :erlang.phash2(:erlang.term_to_binary(config))
  end

  @spec module_names([map()] | []) :: [module()]
  def module_names(source_configs \\ read()) do
    Enum.map(source_configs, &source_module/1)
  end

  @doc false
  def source_module(%{type: type}), do: resolve_source_module(type)
  def source_module(%{"type" => type}), do: resolve_source_module(type)
  def source_module({_id, config}) when is_list(config), do: source_module(Map.new(config))
  def source_module({_id, config}) when is_map(config), do: source_module(config)

  @spec normalize_config(
          {atom() | binary(), map() | keyword()}
          | %{required(:id) => atom() | binary(), required(:type) => atom() | binary()}
        ) :: map()
  defp normalize_config({id, opts}) do
    config_map = ensure_config_map(opts)
    resolve_source_module(extract_type!(config_map))
    require_id(config_map, id)
  end

  defp normalize_config(%{id: id, type: _type} = source_map) do
    resolve_source_module(extract_type!(source_map))
    require_id(source_map, id)
  end

  defp normalize_config(%{"id" => id, "type" => _type} = source_map) do
    resolve_source_module(extract_type!(source_map))
    require_id(source_map, id)
  end

  defp normalize_config(%{type: _type} = source_map) do
    raise ArgumentError, "DAG source config is missing :id: #{inspect(source_map)}"
  end

  defp normalize_config(config) do
    raise ArgumentError,
          "Invalid DAG source config: #{inspect(config)}. Expected {id, opts} with a required :type option."
  end

  defp require_id(_config, id) when is_nil(id) do
    raise ArgumentError, "DAG source config is missing :id"
  end

  defp require_id(config, id) when is_atom(id) or is_binary(id) do
    config
    |> ensure_config_map()
    |> Map.put(:id, id)
    |> Map.new(fn {key, value} -> {normalize_key(key), value} end)
  end

  defp require_id(_config, id), do: raise(ArgumentError, "Invalid DAG source id: #{inspect(id)}")

  defp extract_type!(config) do
    case config do
      %{type: type} ->
        type

      %{"type" => type} ->
        type

      _ ->
        raise ArgumentError,
              "DAG source config is missing required :type option: #{inspect(config)}"
    end
  end

  defp ensure_config_map(opts) when is_map(opts), do: opts
  defp ensure_config_map(opts) when is_list(opts), do: Map.new(opts)

  defp ensure_config_map(opts),
    do: raise(ArgumentError, "Invalid DAG source config: #{inspect(opts)}")

  defp normalize_key(key) when is_atom(key), do: key
  defp normalize_key(key) when is_binary(key), do: String.to_atom(key)
  defp normalize_key(key), do: key

  defp resolve_source_module(module_name) when is_atom(module_name) do
    with false <- MapSet.member?(@known_source_impls, module_name),
         nil <- Map.get(@source_map, module_name, nil) do
      raise ArgumentError, "Unknown DAG source type: #{inspect(module_name)}"
    else
      true -> module_name
      module -> module
    end
  end

  defp resolve_source_module(name) when is_binary(name) do
    case Map.get(@source_map, String.downcase(name), nil) do
      nil -> raise ArgumentError, "Unknown DAG source type: #{inspect(name)}"
      module -> module
    end
  end

  defp resolve_source_module(name) do
    raise ArgumentError, "Invalid DAG source type: #{inspect(name)}"
  end
end
