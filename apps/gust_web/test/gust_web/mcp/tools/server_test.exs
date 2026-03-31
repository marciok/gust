defmodule GustWeb.MCP.Tools.ServerTest do
  use ExUnit.Case, async: true

  alias GustWeb.MCP.Content
  alias GustWeb.MCP.Tool
  alias GustWeb.MCP.Tools.Server

  import Mox

  setup :verify_on_exit!
  setup :set_mox_from_context

  @tool_call_args %{"my_id" => 123}
  @content %Content{type: :text, text: "hello world"}

  def handle(%Tool{name: :mock_tool}, @tool_call_args), do: {false, [@content]}

  setup do
    %{tool: Tool.new(:mock_tool, "just a mock")}
  end

  test "reply/2 forwards list action params to tools list", %{
    tool: %Tool{name: name, description: description} = tool
  } do
    GustWeb.MCPToolsMock |> expect(:all, fn -> [tool] end)
    name = to_string(name)

    assert %{
             "tools" => [
               %{
                 "description" => ^description,
                 "inputSchema" => %{
                   "additionalProperties" => false,
                   "type" => "object"
                 },
                 "name" => ^name
               }
             ]
           } = Server.reply("list", %{})
  end

  test "reply/2 forwards call action params to tools list", %{
    tool: %Tool{name: name} = tool
  } do
    tool = %Tool{tool | handler: __MODULE__}
    GustWeb.MCPToolsMock |> expect(:find, fn ^name -> tool end)
    text = @content.text

    assert %{"content" => [%{"type" => "text", "text" => ^text}], "isError" => false} =
             Server.reply("call", %{
               "name" => name,
               "arguments" => @tool_call_args
             })
  end
end
