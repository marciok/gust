defmodule GustWeb.MCP.Message.Body do
  @moduledoc false

  @jsonrpc_version "2.0"

  defstruct jsonrpc: @jsonrpc_version, id: "", params: Map.new(), method: ""
end
