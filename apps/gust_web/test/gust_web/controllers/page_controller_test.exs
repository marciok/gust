defmodule GustWeb.PageControllerTest do
  use GustWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == ~p"/dags"
  end
end
