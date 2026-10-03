defmodule Gust.DAG.Source.Config do
  @moduledoc """
  Resolves the configured DAG source from `Application.get_env(:gust, :dag_source)`.

  Supported config shapes include:

    * a module atom, such as `Gust.DAG.Source.Folder`
    * a string source name, such as "folder"
    * a tuple of `{module, opts}`
    * a map with a canonical `type` field, such as `%{type: "git", url: ...}`

  Legacy map configs using `name:` are still accepted for compatibility, but `type:`
  is the preferred and documented shape.
  """

  @default_source Gust.DAG.Source.Folder

  @spec read() :: keyword()
  def read do
    case Application.get_env(:gust, :dag_source, @default_source) do
      {module, opts} when is_atom(module) and is_list(opts) ->
        opts

      {module, opts} when is_binary(module) and is_list(opts) ->
        opts

      %{type: _type} = source_config ->
        source_config
        |> Map.delete(:type)
        |> Map.to_list()

      module when is_atom(module) ->
        []

      source_name when is_binary(source_name) ->
        []

      other ->
        raise ArgumentError, "Invalid :dag_source config: #{inspect(other)}"
    end
  end

  @spec module_name(term()) :: module() | nil
  def module_name(source_config \\ Application.get_env(:gust, :dag_source, @default_source)) do
    case source_config do
      {module, _opts} when is_atom(module) -> module
      {module, _opts} when is_binary(module) -> resolve_source_module(module)
      %{type: type} -> resolve_source_module(type)
      module when is_atom(module) -> module
      source_name when is_binary(source_name) -> resolve_source_module(source_name)
      _ -> @default_source
    end
  end

  defp resolve_source_module(module_name) when is_atom(module_name), do: module_name

  defp resolve_source_module(source_name) when is_binary(source_name) do
    source_map = %{
      "database" => Gust.DAG.Source.Database,
      "folder" => Gust.DAG.Source.Folder,
      "git" => Gust.DAG.Source.Git,
      "gitwebhook" => Gust.DAG.Source.GitWebhook,
      "s3" => Gust.DAG.Source.S3
    }

    Map.get(source_map, String.downcase(source_name), nil) ||
      raise ArgumentError, "Unknown DAG source: #{inspect(source_name)}"
  end

  defp resolve_source_module(name) do
    raise ArgumentError, "Invalid DAG source name: #{inspect(name)}"
  end
end
