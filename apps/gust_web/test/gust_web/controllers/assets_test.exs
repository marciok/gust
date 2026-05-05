defmodule GustWeb.Dashboard.AssetsTest do
  use GustWeb.ConnCase

  alias GustWeb.Dashboard.Assets

  describe "init/1" do
    test "accepts :css" do
      assert Assets.init(:css) == :css
    end

    test "accepts :js" do
      assert Assets.init(:js) == :js
    end
  end

  describe "call/2" do
    test "serves css with correct headers", %{conn: conn} do
      conn = Assets.call(conn, :css)

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["text/css"]
      assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000, immutable"]
      assert conn.halted
    end

    test "serves js with correct headers", %{conn: conn} do
      conn = Assets.call(conn, :js)

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["text/javascript"]
      assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000, immutable"]
      assert conn.halted
    end

    test "skips csrf protection", %{conn: conn} do
      conn = Assets.call(conn, :css)

      assert conn.private[:plug_skip_csrf_protection] == true
    end
  end

  describe "current_hash/1" do
    test "returns md5 hex for css" do
      hash = Assets.current_hash(:css)

      assert is_binary(hash)
      assert String.match?(hash, ~r/^[0-9a-f]{32}$/)
    end

    test "returns md5 hex for js" do
      hash = Assets.current_hash(:js)

      assert is_binary(hash)
      assert String.match?(hash, ~r/^[0-9a-f]{32}$/)
    end
  end

  describe "dashboard images" do
    test "serves images from gust_web under the dashboard path", %{conn: conn} do
      conn = get(conn, ~g"/images/gust-logo.png")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["image/png"]
      assert conn.resp_body != ""
    end
  end
end
