defmodule GustWeb.MCP.Resources.ReadTest do
  use ExUnit.Case, async: true

  alias GustWeb.MCP.Resource
  alias GustWeb.MCP.Resources.Read

  test "handle/1 returns file contents when the resource exists" do
    uri = "/tmp/gust-mcp-resource-read-success.txt"
    File.write!(uri, "hello world")

    assert %{
             "contents" => [
               %{
                 "uri" => ^uri,
                 "mimeType" => "text/plain",
                 "text" => "hello world"
               }
             ]
           } = Read.handle(Resource.new(uri, "mock_dag"))
  end

  test "handle/1 returns an error message when the resource cannot be read" do
    uri = "/tmp/gust-mcp-resource-read-missing.txt"
    File.rm(uri)

    assert %{
             "contents" => [
               %{
                 "uri" => ^uri,
                 "mimeType" => "text/plain",
                 "text" => "Failed to read resource " <> _
               }
             ]
           } = Read.handle(Resource.new(uri, "missing_dag"))
  end
end
