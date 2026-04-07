defmodule GustWeb.MCP.Resources do
  @moduledoc false

  alias GustWeb.MCP.Resource

  @callback all() :: [Resource.t()]
  @callback find(String.t()) :: Resource.t() | nil

  # coveralls-ignore-start
  def all, do: impl().all()
  def find(uri), do: impl().find(uri)

  defp impl do
    Application.get_env(:gust_web, :mcp_resources, GustWeb.MCP.Resources.List)
  end

  # coveralls-ignore-stop
end
