defmodule GustWeb.MCP.ServerTest do
  use ExUnit.Case, async: true

  alias GustWeb.MCP.Message.Body
  alias GustWeb.MCP.Server

  test "handle/1 returns an empty result for notifications" do
    assert :nocontent =
             Server.handle(%Body{method: "notifications/tools/list_changed"})
  end

  test "decode!/1 returns an empty result for notifications without an id" do
    assert :nocontent =
             Server.decode!(%{
               "jsonrpc" => "2.0",
               "method" => "notifications/tools/list_changed",
               "params" => %{}
             })
  end

  test "handle/1 returns a method not found error for unknown methods with an id" do
    assert %{"jsonrpc" => "2.0", "id" => "probe-1", "error" => %{"code" => -32_601}} =
             Server.handle(%Body{method: "server/discover", id: "probe-1"})
  end

  test "handle/1 returns an empty result for unknown methods without an id" do
    assert :nocontent = Server.handle(%Body{method: "server/discover"})
  end

  test "decode!/1 returns a method not found error for unknown methods with an id" do
    assert %{"jsonrpc" => "2.0", "id" => "probe-1", "error" => %{"code" => -32_601}} =
             Server.decode!(%{
               "jsonrpc" => "2.0",
               "id" => "probe-1",
               "method" => "server/discover",
               "params" => %{}
             })
  end
end
