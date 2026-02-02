defmodule Gust.DAG.Adapter do
  @moduledoc false

  @default_adapters [
    elixir: %{
      parser: Gust.DAG.Parser.Adapters.Elixir,
      runtime: Gust.DAG.Runtime.Adapters.Elixir,
      task_worker: Gust.DAG.TaskWorker.Adapters.Elixir
    }
  ]

  def impl!(adapter_name, key) do
    adapter_name
    |> adapter_config!()
    |> Map.fetch!(key)
  end

  def parser_module!(adapter_name) do
    impl!(adapter_name, :parser)
  end

  def parser_modules do
    adapters()
    |> Keyword.values()
    |> Enum.map(&Map.fetch!(&1, :parser))
  end

  def parser_for_extension(extension) do
    adapters()
    |> Keyword.values()
    |> Enum.find_value(fn %{parser: parser} ->
      if parser.extension() == extension, do: parser, else: nil
    end)
  end

  defp adapter_config!(adapter_name) do
    adapters()
    |> Keyword.fetch!(adapter_name)
  end

  defp adapters do
    configured = Application.get_env(:gust, :dag_adapter, [])

    Keyword.merge(@default_adapters, configured, fn key, default_val, configured_val ->
      if key == :elixir and is_map(default_val) and is_map(configured_val) do
        Map.merge(default_val, configured_val)
      else
        configured_val
      end
    end)
  end
end
