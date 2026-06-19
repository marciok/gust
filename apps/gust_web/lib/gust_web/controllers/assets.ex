defmodule GustWeb.Dashboard.Assets do
  @moduledoc false

  import Plug.Conn

  @phoenix_js_apps [:phoenix, :phoenix_html, :phoenix_live_view]
  @css_segments ~w(priv static assets css app.css)
  @js_segments ~w(priv static assets js app.js)

  @external_resource Path.expand(
                       "../../../priv/static/assets/css/app.css",
                       __DIR__
                     )
  @external_resource Path.expand(
                       "../../../priv/static/assets/js/app.js",
                       __DIR__
                     )

  for app <- @phoenix_js_apps do
    @external_resource Application.app_dir(
                         app,
                         ["priv", "static", "#{app}.js"]
                       )
  end

  def init(asset) when asset in [:css, :js], do: asset

  def call(conn, asset) do
    {contents, content_type} = contents_and_type(asset)

    conn
    |> put_resp_header("content-type", content_type)
    |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
    |> put_private(:plug_skip_csrf_protection, true)
    |> send_resp(200, contents)
    |> halt()
  end

  def current_hash(asset) when asset in [:css, :js] do
    asset
    |> contents()
    |> then(&:crypto.hash(:md5, &1))
    |> Base.encode16(case: :lower)
  end

  defp contents_and_type(:css), do: {contents(:css), "text/css"}
  defp contents_and_type(:js), do: {contents(:js), "text/javascript"}

  defp contents(:css) do
    :gust_web
    |> Application.app_dir(@css_segments)
    |> read_asset("CSS")
  end

  defp contents(:js) do
    phoenix_js =
      Enum.map(@phoenix_js_apps, fn app ->
        app
        |> Application.app_dir(["priv", "static", "#{app}.js"])
        |> read_asset("#{app} JS")
        |> String.replace("//# sourceMappingURL=", "// ")
      end)

    gust_js =
      :gust_web
      |> Application.app_dir(@js_segments)
      |> read_asset("JS")

    Enum.join(phoenix_js, "\n") <> "\n" <> gust_js
  end

  defp read_asset(path, label) do
    case File.read(path) do
      {:ok, contents} ->
        contents

      {:error, reason} ->
        IO.warn("#{label} asset not found at #{path}: #{:file.format_error(reason)}")
        ""
    end
  end
end
