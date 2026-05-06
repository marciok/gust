defmodule GustWeb.MCPRouter do
  @moduledoc """
  Router macro that mounts the Gust MCP server routes inside a chosen scope.

  Import this module into your Phoenix router and call `gust_mcp_server/0`
  inside an API scope. The host router owns the prefix, so you can mount
  these routes anywhere that fits your app:

      import GustWeb.MCPRouter

      scope "/mcp", MyAppWeb do
        pipe_through :api
        gust_mcp_server()
      end

      scope "/gust/mcp", MyAppWeb do
        pipe_through :api
        gust_mcp_server()
      end
  """

  defmacro gust_mcp_server do
    quote do
      post "/server", GustWeb.MCPController, :message

      get "/server/.well-known/oauth-authorization-server",
          GustWeb.WellKnownController,
          :not_found
    end
  end
end
