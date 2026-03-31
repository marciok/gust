defmodule GustWeb.MCP.Tools do
  @moduledoc false

  alias GustWeb.MCP.Tool

  @callback all() :: [Tool.t()]
  @callback find(String.t()) :: Tool.t()

  # coveralls-ignore-start
  def all, do: impl().all()
  def find(name), do: impl().find(name)

  defp impl do
    Application.get_env(:gust_web, :mcp_tools, GustWeb.MCP.Tools.List)
  end

  # coveralls-ignore-stop
end
