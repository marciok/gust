defmodule GustWeb.Dashboard.Assets do
  @moduledoc false
  import Plug.Conn

  phoenix_js_paths =
    for app <- [:phoenix, :phoenix_html, :phoenix_live_view] do
      path = Application.app_dir(app, ["priv", "static", "#{app}.js"])
      Module.put_attribute(__MODULE__, :external_resource, path)
      path
    end

  @phoenix_js_paths phoenix_js_paths

  @css_path Application.app_dir(:gust_web, ["priv", "static", "assets", "css", "app.css"])
  @external_resource @css_path

  @js_path Application.app_dir(:gust_web, ["priv", "static", "assets", "js", "app.js"])
  @external_resource @js_path

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

  defp contents_and_type(:css), do: {contents(:css), "text/css"}
  defp contents_and_type(:js), do: {contents(:js), "text/javascript"}

  @doc """
  Returns the current hash for the given `asset`.
  """
  def current_hash(asset) when asset in [:css, :js] do
    asset
    |> contents()
    |> then(&:crypto.hash(:md5, &1))
    |> Base.encode16(case: :lower)
  end

  defp contents(:css) do
    read_asset(@css_path, "CSS")
  end

  defp contents(:js) do
    phoenix_js =
      for path <- @phoenix_js_paths do
        path |> File.read!() |> String.replace("//# sourceMappingURL=", "// ")
      end

    Enum.join(phoenix_js, "\n") <> "\n" <> read_asset(@js_path, "JS")
  end

  defp read_asset(path, label) do
    case File.read(path) do
      {:ok, contents} ->
        contents

      {:error, _} ->
        IO.warn("#{label} asset not found at #{path}, run mix assets.build")
        ""
    end
  end
end
