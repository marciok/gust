defmodule GustWeb.MCPControllerTest do
  use GustWeb.ConnCase, async: true
  import Mox

  alias GustWeb.MCP.Content
  alias GustWeb.MCP.Tool

  setup :verify_on_exit!
  setup :set_mox_from_context

  @protocol_version "2025-03-26"
  @jsonrpc "2.0"
  @tool_call_args %{"limit" => 10, "offset" => 2}
  @content %Content{type: :text, text: "ok"}
  @server_info %{
    "name" => "gust-mcp",
    "version" => "0.1.0"
  }

  def handle(%Tool{name: :mock_tool}, @tool_call_args), do: {false, [@content]}

  test "POST /mcp accepts initialize requests", %{conn: conn} do
    result = %{
      "protocolVersion" => @protocol_version,
      "capabilities" => %{
        "tools" => %{}
      },
      "serverInfo" => @server_info
    }

    response = %{"jsonrpc" => @jsonrpc, "id" => "init-1", "result" => result}

    conn =
      post(conn, "/mcp/server", %{
        "jsonrpc" => @jsonrpc,
        "id" => "init-1",
        "method" => "initialize",
        "params" => %{}
      })

    assert ^response = json_response(conn, 200)
  end

  test "POST /mcp list tools", %{conn: conn} do
    tool = Tool.new(:mock_tool, "just a mock")
    GustWeb.MCPToolsMock |> expect(:all, fn -> [tool] end)

    tools = %{
      "tools" => [
        %{
          "name" => "mock_tool",
          "description" => "just a mock",
          "inputSchema" => %{
            "type" => "object",
            "additionalProperties" => false
          }
        }
      ]
    }

    response = %{"jsonrpc" => "2.0", "id" => "init-2", "result" => tools}

    conn =
      post(conn, "/mcp/server", %{
        "jsonrpc" => @jsonrpc,
        "id" => "init-2",
        "method" => "tools/list",
        "params" => %{}
      })

    assert ^response = json_response(conn, 200)
  end

  test "POST /mcp tools call forwards params to tools content", %{conn: conn} do
    tool = %Tool{Tool.new(:mock_tool, "just a mock") | handler: __MODULE__}
    GustWeb.MCPToolsMock |> expect(:find, fn "mock_tool" -> tool end)

    result = %{"content" => [%{"type" => "text", "text" => "ok"}], "isError" => false}
    response = %{"jsonrpc" => @jsonrpc, "id" => "call-1", "result" => result}

    conn =
      post(conn, "/mcp/server", %{
        "jsonrpc" => @jsonrpc,
        "id" => "call-1",
        "method" => "tools/call",
        "params" => %{
          "name" => "mock_tool",
          "arguments" => @tool_call_args
        }
      })

    assert ^response = json_response(conn, 200)
  end
end
