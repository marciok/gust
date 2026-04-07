defmodule GustWeb.MCP.Resources.List do
  @moduledoc false
  @behaviour GustWeb.MCP.Resources

  alias Gust.DAG.Definition
  alias Gust.DAG.Loader
  alias GustWeb.MCP.Resource

  def find(uri) do
    all() |> Enum.find(&(&1.uri == uri))
  end

  def all do
    for {_id, {:ok, %Definition{file_path: file_path, name: name}}} <- Loader.get_definitions() do
      Resource.new(file_path, name)
    end
  end
end
