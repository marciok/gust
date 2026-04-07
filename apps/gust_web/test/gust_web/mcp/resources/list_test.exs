defmodule GustWeb.MCP.Resources.ListTest do
  use ExUnit.Case, async: true

  import Mox

  alias Gust.DAG.Definition
  alias GustWeb.MCP.Resource
  alias GustWeb.MCP.Resources.List

  setup :verify_on_exit!
  setup :set_mox_from_context

  test "all/0 returns the supported MCP resources and ignores non-ok loader entries" do
    GustWeb.DAGLoaderMock
    |> expect(:get_definitions, fn ->
      %{
        1 =>
          {:ok,
           %Definition{name: "daily_stock_decider", file_path: "/tmp/daily_stock_decider.ex"}},
        2 => {:error, :parse_failed}
      }
    end)

    assert List.all() == [
             %Resource{
               uri: "/tmp/daily_stock_decider.ex",
               name: "daily_stock_decider",
               mime_type: "text/plain"
             }
           ]
  end

  test "find/1 returns a resource by its uri" do
    GustWeb.DAGLoaderMock
    |> expect(:get_definitions, fn ->
      %{
        1 =>
          {:ok,
           %Definition{name: "daily_stock_decider", file_path: "/tmp/daily_stock_decider.ex"}}
      }
    end)

    assert %Resource{
             uri: "/tmp/daily_stock_decider.ex",
             name: "daily_stock_decider",
             mime_type: "text/plain"
           } = List.find("/tmp/daily_stock_decider.ex")
  end

  test "find/1 returns nil when the uri is unknown" do
    GustWeb.DAGLoaderMock
    |> expect(:get_definitions, fn ->
      %{
        1 =>
          {:ok,
           %Definition{name: "daily_stock_decider", file_path: "/tmp/daily_stock_decider.ex"}}
      }
    end)

    assert List.find("/tmp/missing_dag.ex") == nil
  end
end
