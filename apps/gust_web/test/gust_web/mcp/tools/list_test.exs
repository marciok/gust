defmodule GustWeb.MCP.Tools.ListTest do
  use ExUnit.Case, async: true

  alias GustWeb.MCP.Tool
  alias GustWeb.MCP.Tools.Call
  alias GustWeb.MCP.Tools.List

  test "all/0 returns the supported MCP tools" do
    tools = List.all()

    assert Enum.map(tools, & &1.name) == [
             :list_dags,
             :list_secrets,
             :query_dag_run,
             :get_dag_def,
             :get_tasks_on_run,
             :restart_run,
             :restart_task,
             :cancel_task,
             :trigger_dag_run
           ]

    assert Enum.all?(tools, &match?(%Tool{handler: Call}, &1))
  end

  test "all/0 defines query_dag_run with required dag name and pagination bounds" do
    tool = Enum.find(List.all(), &(&1.name == :query_dag_run))

    assert %Tool{
             description: "Query DAG runs for a given DAG name, with optional pagination",
             props: [
               {"dag_name", true,
                %{
                  "description" =>
                    "The DAG name in lowercase. Use underscores for compound names, e.g. my_dag",
                  "type" => "string"
                }},
               {"limit", false,
                %{
                  "default" => 10,
                  "description" =>
                    "Maximum number of runs to return. Defaults to 10 if not specified.",
                  "maximum" => 100,
                  "minimum" => 1,
                  "type" => "integer"
                }},
               {"offset", false,
                %{
                  "default" => 0,
                  "description" =>
                    "Number of runs to skip for pagination. Defaults to 0 if not specified.",
                  "minimum" => 0,
                  "type" => "integer"
                }}
             ]
           } = tool
  end

  test "find/1 returns a tool by its string name" do
    assert %Tool{
             name: :restart_task,
             description: "Restart task for a given task_id",
             props: [
               {"task_id", true, %{"description" => "Task ID", "type" => "integer"}}
             ]
           } = List.find("restart_task")
  end

  test "find/1 returns nil when the tool is unknown" do
    assert List.find("missing_tool") == nil
  end
end
