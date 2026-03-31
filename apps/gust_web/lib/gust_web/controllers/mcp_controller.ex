defmodule GustWeb.MCPController do
  use GustWeb, :controller
  import Plug.Conn

  alias GustWeb.MCP.Server

  def message(conn, params) do
    payload = Server.decode!(params)
    json(conn, payload)
  end
end
