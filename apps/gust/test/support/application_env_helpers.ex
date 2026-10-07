defmodule Gust.ApplicationEnvHelpers do
  @moduledoc false

  def replace_env(key, value) do
    previous = Application.fetch_env(:gust, key)
    Application.put_env(:gust, key, value)

    ExUnit.Callbacks.on_exit(fn ->
      case previous do
        {:ok, previous_value} -> Application.put_env(:gust, key, previous_value)
        :error -> Application.delete_env(:gust, key)
      end
    end)
  end

  def restore_dag_source(value \\ nil) do
    case value do
      nil -> Application.delete_env(:gust, :dag_sources)
      previous -> Application.put_env(:gust, :dag_sources, previous)
    end
  end

  def restore_dag_sources(value \\ nil) do
    case value do
      nil -> Application.delete_env(:gust, :dag_sources)
      previous -> Application.put_env(:gust, :dag_sources, previous)
    end
  end

  def init_dag_source(_context) do
    previous_source = Application.get_env(:gust, :dag_sources)
    previous_sources = Application.get_env(:gust, :dag_sources)

    ExUnit.Callbacks.on_exit(fn ->
      restore_dag_source(previous_source)
      restore_dag_sources(previous_sources)
    end)

    :ok
  end

  def init_idempotent_test(context) do
    init_dag_source(context)
  end

  def put_source(id, type, opts \\ []) when is_binary(id) and is_atom(type) and is_list(opts) do
    Application.put_env(
      :gust,
      :dag_sources,
      [{id, Keyword.merge([type: type], opts)}]
    )
  end

  def put_git_source(opts \\ []) when is_list(opts) do
    put_source("test-git", Gust.DAG.Source.Git, opts)
  end

  def put_database_source(opts \\ []) when is_list(opts) do
    put_source("test-database", Gust.DAG.Source.Database, opts)
  end

  def put_folder_source(opts \\ []) when is_list(opts) do
    put_source("test-folder", Gust.DAG.Source.Folder, opts)
  end

  def put_s3_source(opts \\ []) when is_list(opts) do
    put_source("test-s3", Gust.DAG.Source.S3, opts)
  end

  def put_git_webhook_source(opts \\ []) when is_list(opts) do
    put_source("test-github", Gust.DAG.Source.GitWebhook, opts)
  end
end
