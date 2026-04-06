defmodule GustWeb.MCP.Tools.CallTest do
  use Gust.DataCase, async: true

  import Mox
  import Gust.FlowsFixtures

  alias Gust.DAG.Definition
  alias GustWeb.MCP.Content
  alias GustWeb.MCP.Tool
  alias GustWeb.MCP.Tools.Call
  alias GustWeb.MCP.Tools.List

  setup :verify_on_exit!
  setup :set_mox_from_context

  setup do
    dag_def = %Definition{
      name: "definition_dag",
      adapter: :elixir,
      options: [schedule: "@hourly"],
      tasks: %{
        "extract_data" => %{downstream: MapSet.new(["publish_data"]), upstream: MapSet.new()},
        "publish_data" => %{downstream: MapSet.new(), upstream: MapSet.new(["extract_data"])}
      },
      stages: [["extract_data"], ["publish_data"]],
      error: %{},
      mod: Gust.Example.DefinitionDag,
      file_path: "/tmp/dags/definition_dag.ex"
    }

    %{dag_def: dag_def}
  end

  test "handle/2 returns text content for loaded DAG definitions and ignores non-ok entries", %{
    dag_def: dag_def
  } do
    dag = dag_fixture(%{name: "daily_stock_decider"})

    GustWeb.DAGLoaderMock
    |> expect(:get_definitions, fn ->
      %{
        dag.id => {:ok, dag_def},
        99 => {:error, :parse_failed}
      }
    end)

    assert {false, [%Content{} = content]} =
             Call.handle(%Tool{name: :list_dags}, %{"unused" => true})

    assert content.text == dag_definition_text(dag.id, dag_def, true)
  end

  test "handle/2 returns an empty content list when no DAG definitions are available" do
    GustWeb.DAGLoaderMock
    |> expect(:get_definitions, fn -> %{} end)

    assert {false, []} = Call.handle(%Tool{name: :list_dags}, %{})
  end

  test "handle/2 returns text content for secrets" do
    secret_1 =
      secret_fixture(%{
        name: "FIRST_SECRET",
        value: "alpha",
        value_type: :string
      })

    secret_2 =
      secret_fixture(%{
        name: "SECOND_SECRET",
        value: ~s({"enabled":true}),
        value_type: :json
      })

    assert {false, contents} = Call.handle(%Tool{name: :list_secrets}, %{})

    assert text_list(contents) |> Enum.sort() == [
             "Name: FIRST_SECRET; ID: #{secret_1.id}; Type: string",
             "Name: SECOND_SECRET; ID: #{secret_2.id}; Type: json"
           ]
  end

  test "handle/2 returns paginated runs for the requested dag ordered by newest first" do
    dag = dag_fixture(%{name: "sample_dag"})

    older_run =
      run_fixture(%{
        dag_id: dag.id,
        status: :failed,
        inserted_at: ~U[2026-01-01 00:00:00Z]
      })

    middle_run =
      run_fixture(%{
        dag_id: dag.id,
        status: :running,
        inserted_at: ~U[2026-01-02 00:00:00Z]
      })

    newest_run =
      run_fixture(%{
        dag_id: dag.id,
        status: :succeeded,
        inserted_at: ~U[2026-01-03 00:00:00Z]
      })

    assert {false, contents} =
             Call.handle(%Tool{name: :query_dag_run}, %{
               "dag_name" => dag.name,
               "limit" => 2,
               "offset" => 1
             })

    assert text_list(contents) == [
             "ID: #{middle_run.id}; Inserted at: #{middle_run.inserted_at}; " <>
               "Updated at: #{middle_run.updated_at}; Status: running",
             "ID: #{older_run.id}; Inserted at: #{older_run.inserted_at}; " <>
               "Updated at: #{older_run.updated_at}; Status: failed"
           ]

    refute run_text(newest_run, :succeeded) in text_list(contents)
  end

  test "handle/2 returns a not found error when query_dag_run receives an unknown dag_name" do
    dag_name = "missing_dag"

    assert {true, contents} =
             Call.handle(%Tool{name: :query_dag_run}, %{
               "dag_name" => dag_name,
               "limit" => 10,
               "offset" => 0
             })

    assert text_list(contents) == [dag_not_found_text(dag_name)]
  end

  test "handle/2 returns dag definition details for the requested dag id", %{dag_def: dag_def} do
    dag = dag_fixture(%{name: "definition_dag"})

    expect_dag_definition(dag, dag_def)

    assert {false, [%Content{} = content]} =
             Call.handle(%Tool{name: :get_dag_def}, %{"dag_id" => dag.id})

    assert content.text == dag_definition_text(dag.id, dag_def, dag.enabled)
  end

  test "handle/2 returns dag definition details for the requested dag name", %{dag_def: dag_def} do
    dag = dag_fixture(%{name: "definition_dag_by_name"})

    expect_dag_definition(dag, dag_def)

    assert {false, [%Content{} = content]} =
             Call.handle(%Tool{name: :get_dag_def}, %{"dag_name" => dag.name})

    assert content.text == dag_definition_text(dag.id, dag_def, dag.enabled)
  end

  test "handle/2 enables a dag, dispatches pending runs, and returns the updated definition", %{
    dag_def: dag_def
  } do
    dag = dag_fixture(%{name: "toggle_enabled_dag"})
    {:ok, dag} = Gust.Flows.toggle_enabled(dag)

    expect_dag_definition(dag, dag_def)

    GustWeb.DAGRunTriggerMock
    |> expect(:dispatch_all_runs, fn dag_id ->
      assert dag_id == dag.id
      nil
    end)

    assert {false, [%Content{} = content]} =
             Call.handle(%Tool{name: :toggle_enabled_dag}, %{"dag_id" => dag.id})

    assert content.text == dag_definition_text(dag.id, dag_def, true)
    assert Gust.Flows.get_dag!(dag.id).enabled
  end

  test "handle/2 disables a dag without dispatching runs and returns the updated definition", %{
    dag_def: dag_def
  } do
    dag = dag_fixture(%{name: "toggle_disabled_dag"})

    expect_dag_definition(dag, dag_def)

    assert {false, [%Content{} = content]} =
             Call.handle(%Tool{name: :toggle_enabled_dag}, %{"dag_id" => dag.id})

    assert content.text == dag_definition_text(dag.id, dag_def, false)
    refute Gust.Flows.get_dag!(dag.id).enabled
  end

  test "handle/2 returns a not found error when get_dag_def receives an unknown dag_name" do
    dag_name = "missing_dag"

    assert {true, contents} =
             Call.handle(%Tool{name: :get_dag_def}, %{"dag_name" => dag_name})

    assert text_list(contents) == [dag_not_found_text(dag_name)]
  end

  test "handle/2 returns task details for the requested run" do
    dag = dag_fixture(%{name: "tasks_dag"})
    run = run_fixture(%{dag_id: dag.id})

    task_1 =
      task_fixture(%{
        run_id: run.id,
        name: "extract_prices",
        status: :failed,
        error: %{"reason" => "boom"},
        result: %{}
      })

    task_2 =
      task_fixture(%{
        run_id: run.id,
        name: "publish_report",
        status: :succeeded,
        error: %{},
        result: %{"ok" => true}
      })

    assert {false, contents} = Call.handle(%Tool{name: :get_tasks_on_run}, %{"run_id" => run.id})

    assert text_list(contents) |> Enum.sort() == [
             task_text(task_1),
             task_text(task_2)
           ]
  end

  test "handle/2 returns logs for the requested task" do
    dag = dag_fixture(%{name: "logs_dag"})
    run = run_fixture(%{dag_id: dag.id})
    task = task_fixture(%{run_id: run.id, name: "extract_prices"})

    log_1 =
      log_fixture(%{
        task_id: task.id,
        content: "Started fetching data",
        level: "info",
        attempt: 1
      })

    log_2 =
      log_fixture(%{
        task_id: task.id,
        content: "Retry scheduled",
        level: "warn",
        attempt: 1
      })

    assert {false, contents} =
             Call.handle(%Tool{name: :get_logs_on_task}, %{"task_id" => task.id})

    assert text_list(contents) |> Enum.sort() == [
             log_text(log_1),
             log_text(log_2)
           ]
  end

  test "handle/2 delegates restart_run to the configured trigger" do
    dag = dag_fixture(%{name: "restartable_dag"})
    run = run_fixture(%{dag_id: dag.id, status: :failed})

    GustWeb.DAGRunTriggerMock
    |> expect(:reset_run, fn %Gust.Flows.Run{id: run_id} = fetched_run ->
      assert run_id == run.id
      fetched_run
    end)

    assert {false, contents} = Call.handle(%Tool{name: :restart_run}, %{"run_id" => run.id})
    assert text_list(contents) == ["Run: #{run.id} was restarted"]
  end

  test "handle/2 delegates restart_task with the dag task graph and task" do
    %{dag: dag, task: task} =
      task_setup("restart_task_dag", %{name: "transform_data", status: :failed})

    tasks_graph = sample_tasks_graph()

    expect_dag_definition(dag, %Definition{tasks: tasks_graph})

    GustWeb.DAGRunTriggerMock
    |> expect(:reset_task, fn graph, fetched_task ->
      assert graph == tasks_graph
      assert fetched_task.id == task.id
      assert fetched_task.name == "transform_data"
      []
    end)

    assert {false, contents} = Call.handle(%Tool{name: :restart_task}, %{"task_id" => task.id})
    assert text_list(contents) == ["Task: #{task.name} was restarted"]
  end

  test "handle/2 cancels a running task via the terminator" do
    %{dag: dag, task: task} =
      task_setup("cancel_running_dag", %{name: "cancel_me", status: :running})

    previous_dag_adapter = Application.get_env(:gust, :dag_adapter)

    on_exit(fn ->
      Application.put_env(:gust, :dag_adapter, previous_dag_adapter)
    end)

    Application.put_env(:gust, :dag_adapter, elixir: %{runtime: __MODULE__})

    expect_dag_definition(dag, %Definition{adapter: :elixir})

    GustWeb.DAGTerminatorMock
    |> expect(:kill_task, fn fetched_task, :cancelled, runtime ->
      assert fetched_task.id == task.id
      assert runtime == __MODULE__
      nil
    end)

    assert {false, contents} = Call.handle(%Tool{name: :cancel_task}, %{"task_id" => task.id})
    assert text_list(contents) == ["Task: #{task.name} was cancelled"]
  end

  test "handle/2 cancels a retrying task timer via the terminator" do
    %{dag: dag, task: task} =
      task_setup("cancel_retrying_dag", %{name: "retry_me", status: :retrying})

    expect_dag_definition(dag, %Definition{adapter: :elixir})

    GustWeb.DAGTerminatorMock
    |> expect(:cancel_timer, fn fetched_task, :cancelled ->
      assert fetched_task.id == task.id
      nil
    end)

    assert {false, contents} = Call.handle(%Tool{name: :cancel_task}, %{"task_id" => task.id})
    assert text_list(contents) == ["Task: #{task.name} retrying cancelled"]
  end

  test "handle/2 creates and dispatches a run for the requested dag" do
    dag = dag_fixture(%{name: "triggerable_dag"})

    GustWeb.DAGRunTriggerMock
    |> expect(:dispatch_run, fn %Gust.Flows.Run{} = run ->
      assert run.dag_id == dag.id
      assert Ecto.assoc_loaded?(run.tasks)
      run
    end)

    assert {false, contents} =
             Call.handle(%Tool{name: :trigger_dag_run}, %{"dag_name" => dag.name})

    [message] = text_list(contents)
    assert String.starts_with?(message, "Run ")
    assert message =~ " triggered"
  end

  test "handle/2 creates and dispatches a run for the requested dag id" do
    dag = dag_fixture(%{name: "triggerable_dag_by_id"})

    GustWeb.DAGRunTriggerMock
    |> expect(:dispatch_run, fn %Gust.Flows.Run{} = run ->
      assert run.dag_id == dag.id
      assert Ecto.assoc_loaded?(run.tasks)
      run
    end)

    assert {false, contents} =
             Call.handle(%Tool{name: :trigger_dag_run}, %{"dag_id" => dag.id})

    [message] = text_list(contents)
    assert String.starts_with?(message, "Run ")
    assert message =~ " triggered"
  end

  test "handle/2 returns a not found error when trigger_dag_run receives an unknown dag_name" do
    dag_name = "missing_dag"

    assert {true, contents} =
             Call.handle(%Tool{name: :trigger_dag_run}, %{"dag_name" => dag_name})

    assert text_list(contents) == [dag_not_found_text(dag_name)]
  end

  test "handle/2 returns a fallback error describing supported properties" do
    tool = List.find("query_dag_run")

    GustWeb.MCPToolsMock
    |> expect(:find, fn "query_dag_run" -> tool end)

    assert {true, contents} =
             Call.handle(%Tool{name: :query_dag_run}, %{"unexpected" => "value"})

    assert text_list(contents) == [
             "Tool query_dag_run supports the following properties: " <>
               "dag_name: The DAG name in lowercase. Use underscores for compound names, e.g. my_dag, " <>
               "limit: Maximum number of runs to return. Defaults to 10 if not specified., " <>
               "offset: Number of runs to skip for pagination. Defaults to 0 if not specified."
           ]
  end

  test "handle/2 falls back to the original tool when the tool registry has no match" do
    GustWeb.MCPToolsMock
    |> expect(:find, fn "unknown_tool" -> nil end)

    assert {true, contents} =
             Call.handle(%Tool{name: :unknown_tool, props: []}, %{"unexpected" => "value"})

    assert text_list(contents) == ["Tool unknown_tool supports no properties."]
  end

  defp expect_dag_definition(dag, dag_def_or_result) do
    GustWeb.DAGLoaderMock
    |> expect(:get_definition, fn dag_id ->
      assert dag_id == dag.id
      {:ok, dag_def_or_result}
    end)
  end

  defp sample_tasks_graph do
    %{
      "transform_data" => %{downstream: MapSet.new(["publish_data"]), upstream: MapSet.new()},
      "publish_data" => %{downstream: MapSet.new(), upstream: MapSet.new(["transform_data"])}
    }
  end

  defp task_setup(dag_name, task_attrs) do
    dag = dag_fixture(%{name: dag_name})
    run = run_fixture(%{dag_id: dag.id})
    task = task_fixture(Map.put(task_attrs, :run_id, run.id))
    %{dag: dag, run: run, task: task}
  end

  defp text_list(contents), do: Enum.map(contents, & &1.text)

  defp dag_definition_text(dag_id, dag_def, enabled) do
    """
    Name: #{dag_def.name}
    ID: #{dag_id}
    Enabled: #{enabled}
    File Path: #{dag_def.file_path}
    Options: #{inspect(dag_def.options)}
    Stages: #{inspect(dag_def.stages)}
    Module: #{dag_def.mod}
    Adapter: #{dag_def.adapter}
    Tasks: #{inspect(dag_def.tasks)}
    Error: #{inspect(dag_def.error)}
    Warnings: #{inspect(dag_def.messages)}
    """
  end

  defp run_text(run, status) do
    "ID: #{run.id}; Inserted at: #{run.inserted_at}; Updated at: #{run.updated_at}; Status: #{status}"
  end

  defp task_text(task) do
    "ID: #{task.id}; Name: #{task.name}, Status: #{task.status}; Error: #{inspect(task.error)}, Result: #{inspect(task.result)}"
  end

  defp log_text(log) do
    "ID: #{log.id}; level: #{log.level}, inserted_at: #{inspect(log.inserted_at)}; Content: #{log.content}"
  end

  defp dag_not_found_text(dag_name) do
    "DAG with name #{dag_name} does not exists. Use list_dags to find available DAG names"
  end
end
