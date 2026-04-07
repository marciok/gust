defmodule GustWeb.WellKnownControllerTest do
  use GustWeb.ConnCase

  test "GET /.well-known/* returns 404", %{conn: conn} do
    conn = get(conn, "/.well-known/appspecific/com.chrome.devtools.json")

    assert conn.status == 404
    assert response(conn, 404) == "Not Found"
  end

  test "HEAD /.well-known/* returns 404", %{conn: conn} do
    conn = head(conn, "/.well-known/apple-app-site-association")

    assert conn.status == 404
    assert response(conn, 404) == ""
  end

  test "GET /mcp/server/.well-known/oauth-authorization-server returns 404", %{conn: conn} do
    conn = get(conn, "/mcp/server/.well-known/oauth-authorization-server")

    assert conn.status == 404
    assert response(conn, 404) == "Not Found"
  end
end
