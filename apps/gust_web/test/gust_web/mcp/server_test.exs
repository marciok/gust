defmodule GustWeb.MCP.ServerTest do
  use ExUnit.Case, async: true

  alias GustWeb.MCP.Message.Body
  alias GustWeb.MCP.Server

  test "handle/1 returns an empty result for notifications" do
    assert %{"jsonrpc" => "2.0", "result" => []} =
             Server.handle(%Body{method: "notifications/tools/list_changed"})
  end

  test "decode!/1 returns an empty result for notifications without an id" do
    assert %{"jsonrpc" => "2.0", "result" => []} =
             Server.decode!(%{
               "jsonrpc" => "2.0",
               "method" => "notifications/tools/list_changed",
               "params" => %{}
             })
  end
end
