defmodule GustWeb.MCP.ResourceTest do
  use ExUnit.Case, async: true

  alias GustWeb.MCP.Resource
  alias GustWeb.MCP.Resources.Read

  test "new/3 builds a resource with the default handler" do
    assert %Resource{
             uri: "/tmp/my_dag.ex",
             name: "my_dag",
             mime_type: "text/plain",
             handler: Read
           } = Resource.new("/tmp/my_dag.ex", "my_dag")
  end

  test "to_map/1 serializes the resource" do
    assert %{
             "uri" => "/tmp/my_dag.ex",
             "name" => "my_dag",
             "mimeType" => "text/plain"
           } = Resource.new("/tmp/my_dag.ex", "my_dag") |> Resource.to_map()
  end
end
