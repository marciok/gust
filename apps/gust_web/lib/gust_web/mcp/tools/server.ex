defmodule GustWeb.MCP.Tools.Server do
  @moduledoc false

  alias GustWeb.MCP.{Content, Tool, Tools}

  def reply("call", %{"name" => name, "arguments" => args}) do
    tool = Tools.find(name)
    {error?, contents} = tool.handler.handle(tool, args)

    %{
      "content" =>
        for content <- contents do
          Content.to_map(content)
        end,
      "isError" => error?
    }
  end

  def reply("list", %{}) do
    %{
      "tools" =>
        for tool <- Tools.all() do
          Tool.to_map(tool)
        end
    }
  end
end
