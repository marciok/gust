defmodule GustWeb.Dashboard.AssetsTest do
  use GustWeb.ConnCase

  alias GustWeb.Dashboard.Assets
  import ExUnit.CaptureIO

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

    test "warns and serves empty content when css asset is missing", %{conn: conn} do
      path = Application.app_dir(:gust_web, ["priv", "static", "assets", "css", "app.css"])
      backup_path = path <> ".bak"

      File.rm(backup_path)

      moved? =
        if File.exists?(path) do
          File.rename!(path, backup_path)
          true
        else
          false
        end

      on_exit(fn ->
        if moved? && File.exists?(backup_path) do
          File.rename!(backup_path, path)
        end
      end)

      warning =
        capture_io(:stderr, fn ->
          conn = Assets.call(conn, :css)
          send(self(), {:asset_conn, conn})
        end)

      assert_receive {:asset_conn, conn}
      assert conn.status == 200
      assert conn.resp_body == ""
      assert warning =~ "CSS asset not found at #{path}, run mix assets.build"
    end
  end

  describe "current_hash/1" do
    test "returns md5 hex for css" do
      hash = Assets.current_hash(:css)

      assert is_binary(hash)
      assert String.match?(hash, ~r/^[0-9a-f]{32}$/)

      conn = Assets.call(build_conn(), :css)
      assert Base.encode16(:crypto.hash(:md5, conn.resp_body), case: :lower) == hash
    end

    test "returns md5 hex for js" do
      hash = Assets.current_hash(:js)

      assert is_binary(hash)
      assert String.match?(hash, ~r/^[0-9a-f]{32}$/)

      conn = Assets.call(build_conn(), :js)
      assert Base.encode16(:crypto.hash(:md5, conn.resp_body), case: :lower) == hash
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
