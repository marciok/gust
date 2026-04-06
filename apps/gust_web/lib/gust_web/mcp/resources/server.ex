defmodule GustWeb.MCP.Resources.Server do
  @moduledoc false

  alias GustWeb.MCP.{Resource, Resources}

  def reply("list", _params) do
    %{
      "resources" =>
        for resource <- Resources.all() do
          Resource.to_map(resource)
        end
    }
  end

  def reply("read", %{"uri" => uri}) do
    resource = Resources.find(uri)
    resource.handler.handle(resource)
  end
end
