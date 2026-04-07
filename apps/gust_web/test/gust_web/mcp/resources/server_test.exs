defmodule GustWeb.MCP.Resources.ServerTest do
  use ExUnit.Case, async: true

  alias GustWeb.MCP.Resource
  alias GustWeb.MCP.Resources.Server

  import Mox

  setup :verify_on_exit!
  setup :set_mox_from_context

  @uri "/tmp/mock_dag.ex"

  def handle(%Resource{uri: @uri, mime_type: "text/plain"}) do
    %{
      "contents" => [
        %{
          "uri" => @uri,
          "mimeType" => "text/plain",
          "text" => "hello world"
        }
      ]
    }
  end

  setup do
    %{resource: Resource.new(@uri, "mock_dag")}
  end

  test "reply/2 forwards list action params to resources list", %{resource: resource} do
    GustWeb.MCPResourcesMock |> expect(:all, fn -> [resource] end)

    assert %{
             "resources" => [
               %{
                 "uri" => @uri,
                 "name" => "mock_dag",
                 "mimeType" => "text/plain"
               }
             ]
           } = Server.reply("list", %{})
  end

  test "reply/2 forwards read action params to resources list", %{
    resource: %Resource{uri: uri} = resource
  } do
    resource = %Resource{resource | handler: __MODULE__}
    GustWeb.MCPResourcesMock |> expect(:find, fn ^uri -> resource end)

    assert %{
             "contents" => [
               %{
                 "uri" => ^uri,
                 "mimeType" => "text/plain",
                 "text" => "hello world"
               }
             ]
           } = Server.reply("read", %{"uri" => uri})
  end

  test "reply/2 returns an empty list for templates/list" do
    assert %{"resources" => []} = Server.reply("templates/list", %{})
  end
end
