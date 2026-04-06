defmodule GustWeb.MCP.Server do
  @moduledoc false

  alias GustWeb.MCP.Message.Body
  alias GustWeb.MCP.{Resources, Tools}

  @protocol_version "2025-03-26"
  @jsonrpc_version "2.0"
  @info %{
    "name" => "gust-mcp",
    "version" => "0.1.0"
  }

  def decode!(
        %{
          "id" => id,
          "jsonrpc" => @jsonrpc_version,
          "method" => method
        } = body
      ) do
    handle(%Body{method: method, id: id, params: body["params"]})
  end

  def decode!(
        %{
          "jsonrpc" => @jsonrpc_version,
          "method" => method
        } = body
      ) do
    handle(%Body{method: method, params: body["params"]})
  end

  def handle(%Body{method: "initialize", id: id}) do
    result = %{
      "protocolVersion" => @protocol_version,
      "capabilities" => %{
        "tools" => %{},
        "resources" => %{}
      },
      "serverInfo" => @info
    }

    jsonrpc(id, result)
  end

  def handle(%Body{method: "notifications/" <> _notif_type}) do
    %{"jsonrpc" => @jsonrpc_version, "result" => []}
  end

  def handle(%Body{method: "tools/" <> action, id: id} = body) do
    jsonrpc(id, Tools.Server.reply(action, body.params))
  end

  def handle(%Body{method: "resources/" <> action, id: id} = body) do
    jsonrpc(id, Resources.Server.reply(action, body.params))
  end

  defp jsonrpc(id, result) do
    %{"jsonrpc" => @jsonrpc_version, "id" => id, "result" => result}
  end
end
