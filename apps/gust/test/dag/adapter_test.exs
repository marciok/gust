defmodule Gust.DAG.AdapterTest do
  use Gust.DataCase, async: false

  alias Gust.DAG.Adapter

  setup do
    previous_adapters = Application.get_env(:gust, :dag_adapter, [])

    on_exit(fn ->
      Application.put_env(:gust, :dag_adapter, previous_adapters)
    end)

    :ok
  end

  describe "impl!/2" do
    test "returns default elixir implementation when no config is provided" do
      Application.put_env(:gust, :dag_adapter, [])

      assert Adapter.impl!(:elixir, :parser) == Gust.DAG.Parser.Adapters.Elixir
      assert Adapter.impl!(:elixir, :runtime) == Gust.DAG.Runtime.Adapters.Elixir
      assert Adapter.impl!(:elixir, :task_worker) == Gust.DAG.TaskWorker.Adapters.Elixir
    end

    test "fetches configured adapter implementation for a key" do
      Application.put_env(:gust, :dag_adapter,
        elixir: %{
          parser: Gust.DAG.Parser.Adapters.Elixir,
          runtime: :runtime_impl,
          task_worker: :task_worker_impl
        },
        mock: %{
          parser: :mock_parser,
          runtime: :mock_runtime,
          task_worker: :mock_task_worker
        }
      )

      assert Adapter.impl!(:elixir, :parser) == Gust.DAG.Parser.Adapters.Elixir
      assert Adapter.impl!(:elixir, :runtime) == :runtime_impl
      assert Adapter.impl!(:elixir, :task_worker) == :task_worker_impl
      assert Adapter.impl!(:mock, :parser) == :mock_parser
    end

    test "raises when the adapter is not configured" do
      Application.put_env(:gust, :dag_adapter, [])

      assert_raise KeyError, fn ->
        Adapter.impl!(:missing, :parser)
      end
    end

    test "raises when the key is missing from the adapter config" do
      Application.put_env(:gust, :dag_adapter,
        custom: %{
          parser: :parser_impl
        }
      )

      assert_raise KeyError, fn ->
        Adapter.impl!(:custom, :runtime)
      end
    end

    test "merges custom elixir config with defaults and keeps additional adapters" do
      Application.put_env(:gust, :dag_adapter,
        elixir: %{
          runtime: :custom_runtime
        },
        custom: %{
          parser: :custom_parser,
          runtime: :custom_runtime,
          task_worker: :custom_task_worker
        }
      )

      assert Adapter.impl!(:elixir, :parser) == Gust.DAG.Parser.Adapters.Elixir
      assert Adapter.impl!(:elixir, :runtime) == :custom_runtime
      assert Adapter.impl!(:elixir, :task_worker) == Gust.DAG.TaskWorker.Adapters.Elixir
      assert Adapter.impl!(:custom, :parser) == :custom_parser
    end
  end

  describe "parser_module!/1" do
    test "returns the parser module for the adapter" do
      Application.put_env(:gust, :dag_adapter,
        elixir: %{
          parser: Gust.DAG.Parser.Adapters.Elixir,
          runtime: :runtime_impl,
          task_worker: :task_worker_impl
        }
      )

      assert Adapter.parser_module!(:elixir) == Gust.DAG.Parser.Adapters.Elixir
    end
  end

  describe "parser_for_extension/1" do
    test "returns a parser module that matches the extension" do
      Application.put_env(:gust, :dag_adapter,
        elixir: %{
          parser: Gust.DAG.Parser.Adapters.Elixir,
          runtime: :runtime_impl,
          task_worker: :task_worker_impl
        }
      )

      assert Adapter.parser_for_extension(".ex") == Gust.DAG.Parser.Adapters.Elixir
    end

    test "returns nil when no parser matches the extension" do
      Application.put_env(:gust, :dag_adapter,
        elixir: %{
          parser: Gust.DAG.Parser.Adapters.Elixir,
          runtime: :runtime_impl,
          task_worker: :task_worker_impl
        }
      )

      assert Adapter.parser_for_extension(".unknown") == nil
    end
  end
end
