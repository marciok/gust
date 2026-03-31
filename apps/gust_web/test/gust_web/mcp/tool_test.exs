defmodule GustWeb.MCP.ToolTest do
  use ExUnit.Case, async: true

  alias GustWeb.MCP.Tool
  alias GustWeb.MCP.Tools.Call

  test "new/3 builds a tool with the default handler" do
    props = [Tool.prop("dag_id", "integer", "DAG ID", required: true)]

    assert %Tool{
             name: :get_dag_def,
             description: "Get dag definition",
             props: ^props,
             handler: Call
           } = Tool.new(:get_dag_def, "Get dag definition", props)
  end

  test "prop/4 builds property specs with bounds and required flag" do
    assert {"limit", false,
            %{
              "default" => 10,
              "description" => "Maximum number of runs",
              "maximum" => 100,
              "minimum" => 1,
              "type" => "integer"
            }} =
             Tool.prop("limit", "integer", "Maximum number of runs",
               default: 10,
               minimum: 1,
               maximum: 100
             )

    assert {"dag_name", true,
            %{
              "description" => "DAG name",
              "type" => "string"
            }} = Tool.prop("dag_name", "string", "DAG name", required: true)
  end

  test "to_map/1 builds input schema with properties and required fields" do
    tool =
      Tool.new(:query_dag_run, "Query DAG runs", [
        Tool.prop("dag_name", "string", "DAG name", required: true),
        Tool.prop("limit", "integer", "Maximum number of runs", default: 10, minimum: 1)
      ])

    assert %{
             "name" => "query_dag_run",
             "description" => "Query DAG runs",
             "inputSchema" => %{
               "type" => "object",
               "additionalProperties" => false,
               "required" => ["dag_name"],
               "properties" => %{
                 "dag_name" => %{
                   "description" => "DAG name",
                   "type" => "string"
                 },
                 "limit" => %{
                   "default" => 10,
                   "description" => "Maximum number of runs",
                   "minimum" => 1,
                   "type" => "integer"
                 }
               }
             }
           } = Tool.to_map(tool)
  end

  test "to_map/1 omits properties and required when the tool has no props" do
    assert %{
             "name" => "list_dags",
             "description" => "List all available DAGs.",
             "inputSchema" => %{
               "type" => "object",
               "additionalProperties" => false
             }
           } = Tool.new(:list_dags, "List all available DAGs.") |> Tool.to_map()
  end
end
