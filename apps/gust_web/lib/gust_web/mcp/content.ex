defmodule GustWeb.MCP.Content do
  @moduledoc false

  defstruct type: :text, text: ""

  def new(text) do
    %__MODULE__{type: :text, text: text}
  end

  def to_map(%__MODULE__{type: :text, text: text}) do
    %{
      "type" => "text",
      "text" => text
    }
  end
end
