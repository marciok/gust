defmodule GustWeb.MCPController do
  use GustWeb, :controller

  alias GustWeb.MCP.Server

  def message(conn, params) do
    payload = Server.decode!(params)

    case payload do
      %{"jsonrpc" => _} = data ->
        json(conn, data)

      :nocontent ->
        send_resp(conn, 204, "")
    end
  end
end
