defmodule GustWeb.MCP.Tools.List do
  @moduledoc false
  @behaviour GustWeb.MCP.Tools

  alias GustWeb.MCP.Tool

  def find(name) do
    all() |> Enum.find(&(to_string(&1.name) == name))
  end

  def all do
    [
      Tool.new(:list_dags, "List all available DAGs."),
      Tool.new(:list_secrets, "List all available Secrets"),
      Tool.new(
        :query_dag_run,
        "Query DAG runs for a given DAG name, with optional pagination",
        [
          Tool.prop(
            "dag_name",
            "string",
            "The DAG name in lowercase. Use underscores for compound names, e.g. my_dag",
            required: true
          ),
          Tool.prop(
            "limit",
            "integer",
            "Maximum number of runs to return. Defaults to 10 if not specified.",
            default: 10,
            minimum: 1,
            maximum: 100,
            required: true
          ),
          Tool.prop(
            "offset",
            "integer",
            "Number of runs to skip for pagination. Defaults to 0 if not specified.",
            default: 0,
            minimum: 0,
            required: true
          )
        ]
      ),
      Tool.new(
        :get_dag_def,
        "Get dag definition for a given dag_id",
        [Tool.prop("dag_id", "integer", "DAG ID", required: true)]
      ),
      Tool.new(
        :toggle_enabled_dag,
        "Toggle DAG enabled property",
        [Tool.prop("dag_id", "integer", "DAG ID", required: true)]
      ),
      Tool.new(
        :get_tasks_on_run,
        "Get tasks for a given run",
        [Tool.prop("run_id", "integer", "Run ID", required: true)]
      ),
      Tool.new(
        :get_logs_on_task,
        "Get logs for a given task",
        [Tool.prop("task_id", "integer", "Task ID", required: true)]
      ),
      Tool.new(
        :restart_run,
        "Restart run for a given run_id",
        [
          Tool.prop("run_id", "integer", "Run ID", required: true)
        ]
      ),
      Tool.new(
        :restart_task,
        "Restart task for a given task_id",
        [
          Tool.prop("task_id", "integer", "Task ID", required: true)
        ]
      ),
      Tool.new(
        :cancel_task,
        "Cancel task for a given task_id, when cancelling task the run will also be cancelled",
        [
          Tool.prop("task_id", "integer", "Task ID", required: true)
        ]
      ),
      Tool.new(
        :trigger_dag_run,
        "Trigger a dag run with a given dag name",
        [
          Tool.prop(
            "dag_name",
            "string",
            "Its a single string, lower cases, if its a composed name use underline ex: my_dag",
            required: true
          )
        ]
      )
    ]
  end
end
