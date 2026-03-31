defmodule GustWeb.MCP.Tool do
  @moduledoc false

  defstruct [:name, :description, :props, handler: GustWeb.MCP.Tools.Call]

  def new(name, description, props \\ []) do
    %__MODULE__{
      name: name,
      description: description,
      props: props
    }
  end

  def to_map(%__MODULE__{name: name, description: description, props: props}) do
    %{
      "name" => to_string(name),
      "description" => description,
      "inputSchema" => input_schema(props)
    }
  end

  defp input_schema(props) do
    %{
      "type" => "object",
      "additionalProperties" => false
    }
    |> put_properties(
      for {name, _required, specs} <- props, into: %{} do
        {name, specs}
      end
    )
    |> put_required(
      for {name, true, _spec} <- props do
        name
      end
    )
  end

  def prop(name, type, description, options \\ []) do
    {bound_specs, other_opts} = Keyword.split(options, [:default, :minimum, :maximum])
    required = Keyword.get(other_opts, :required, false)

    specs =
      for {key, value} <- bound_specs, into: %{} do
        {Atom.to_string(key), value}
      end

    {name, required, Map.merge(%{"type" => type, "description" => description}, specs)}
  end

  defp put_properties(map, properties) when map_size(properties) == 0, do: map
  defp put_properties(map, properties), do: Map.put(map, "properties", properties)

  defp put_required(map, []), do: map
  defp put_required(map, required), do: Map.put(map, "required", required)
end
