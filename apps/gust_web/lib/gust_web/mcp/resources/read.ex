defmodule GustWeb.MCP.Resources.Read do
  @moduledoc false

  alias GustWeb.MCP.Resource

  def handle(%Resource{uri: uri, mime_type: mime_type}) do
    text =
      case File.read(uri) do
        {:ok, content} ->
          content

        {:error, reason} ->
          "Failed to read resource #{uri}: #{:file.format_error(reason)}"
      end

    %{
      "contents" => [
        %{
          "uri" => uri,
          "mimeType" => mime_type,
          "text" => text
        }
      ]
    }
  end
end
