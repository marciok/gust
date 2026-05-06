defmodule GustWeb.MCPRouterTest do
  use GustWeb.ConnCase, async: true

  @mcp_paths [
    "/mcp/server",
    "/mcp/server/.well-known/oauth-authorization-server"
  ]

  test "gust_mcp_server/0 defines MCP routes inside a scope" do
    paths = router_paths("/mcp")

    Enum.each(@mcp_paths, fn path ->
      assert path in paths
    end)
  end

  test "gust_mcp_server/0 uses whatever host scope prefix is provided" do
    paths = router_paths("/gust/mcp")

    assert "/gust/mcp/server" in paths
    assert "/gust/mcp/server/.well-known/oauth-authorization-server" in paths
  end

  defp router_paths(scope_path) do
    module = build_router(scope_path)

    module.__routes__()
    |> Enum.map(& &1.path)
  end

  defp build_router(scope_path) do
    module = Module.concat(__MODULE__, "TestRouter#{System.unique_integer([:positive])}")

    {:module, ^module, _, _} =
      Module.create(
        module,
        quote do
          use Phoenix.Router
          import GustWeb.MCPRouter

          pipeline :api do
            plug :accepts, ["json"]
          end

          scope unquote(scope_path) do
            pipe_through :api
            gust_mcp_server()
          end
        end,
        Macro.Env.location(__ENV__)
      )

    module
  end
end
