defmodule GustWeb.MCP.Resource do
  @moduledoc false

  defstruct [:uri, :name, mime_type: "text/plain", handler: GustWeb.MCP.Resources.Read]

  def new(uri, name, mime_type \\ "text/plain") do
    %__MODULE__{
      uri: uri,
      name: name,
      mime_type: mime_type
    }
  end

  def to_map(%__MODULE__{uri: uri, name: name, mime_type: mime_type}) do
    %{
      "uri" => uri,
      "name" => name,
      "mimeType" => mime_type
    }
  end
end
