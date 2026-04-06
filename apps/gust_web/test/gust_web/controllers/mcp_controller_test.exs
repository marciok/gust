defmodule GustWeb.MCPControllerTest do
  use GustWeb.ConnCase, async: true
  import Mox

  alias GustWeb.MCP.Content
  alias GustWeb.MCP.Resource
  alias GustWeb.MCP.Tool

  setup :verify_on_exit!
  setup :set_mox_from_context

  @protocol_version "2025-03-26"
  @jsonrpc "2.0"
  @tool_call_args %{"limit" => 10, "offset" => 2}
  @content %Content{type: :text, text: "ok"}
  @resource_uri "/tmp/mock_dag.ex"
  @server_info %{
    "name" => "gust-mcp",
    "version" => "0.1.0"
  }

  def handle(%Tool{name: :mock_tool}, @tool_call_args), do: {false, [@content]}

  def handle(%Resource{uri: @resource_uri, mime_type: "text/plain"}) do
    %{
      "contents" => [
        %{
          "uri" => @resource_uri,
          "mimeType" => "text/plain",
          "text" => "ok"
        }
      ]
    }
  end

  test "POST /mcp accepts initialize requests", %{conn: conn} do
    result = %{
      "protocolVersion" => @protocol_version,
      "capabilities" => %{
        "tools" => %{},
        "resources" => %{}
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

  test "POST /mcp list resources", %{conn: conn} do
    resource = Resource.new(@resource_uri, "mock_dag")
    GustWeb.MCPResourcesMock |> expect(:all, fn -> [resource] end)

    resources = %{
      "resources" => [
        %{
          "uri" => @resource_uri,
          "name" => "mock_dag",
          "mimeType" => "text/plain"
        }
      ]
    }

    response = %{"jsonrpc" => "2.0", "id" => "init-3", "result" => resources}

    conn =
      post(conn, "/mcp/server", %{
        "jsonrpc" => @jsonrpc,
        "id" => "init-3",
        "method" => "resources/list",
        "params" => %{}
      })

    assert ^response = json_response(conn, 200)
  end

  test "POST /mcp resources read forwards params to resource handler", %{conn: conn} do
    resource = %Resource{Resource.new(@resource_uri, "mock_dag") | handler: __MODULE__}
    GustWeb.MCPResourcesMock |> expect(:find, fn @resource_uri -> resource end)

    result = %{
      "contents" => [
        %{
          "uri" => @resource_uri,
          "mimeType" => "text/plain",
          "text" => "ok"
        }
      ]
    }

    response = %{"jsonrpc" => @jsonrpc, "id" => "read-1", "result" => result}

    conn =
      post(conn, "/mcp/server", %{
        "jsonrpc" => @jsonrpc,
        "id" => "read-1",
        "method" => "resources/read",
        "params" => %{
          "uri" => @resource_uri
        }
      })

    assert ^response = json_response(conn, 200)
  end
end
