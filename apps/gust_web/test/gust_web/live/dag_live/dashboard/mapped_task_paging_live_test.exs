defmodule GustWeb.DagLive.Dashboard.MappedTaskPagingLiveTest do
  use GustWeb.ConnCase

  import Gust.FlowsFixtures
  import Mox
  import Phoenix.LiveViewTest

  alias Gust.DAG.Definition
  alias Gust.Flows

  setup :verify_on_exit!

  @task_name "insert_models"

  setup do
    previous = Application.fetch_env(:gust, :mapped_tasks)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:gust, :mapped_tasks, value)
        :error -> Application.delete_env(:gust, :mapped_tasks)
      end
    end)

    dag = dag_fixture(%{name: "mapped_paging_dag"})
    run = run_fixture(%{dag_id: dag.id})

    [first, second, third] =
      for {status, index} <- Enum.with_index([:succeeded, :running, :created]) do
        task_fixture(%{run_id: run.id, name: @task_name, status: status, map_index: index})
      end

    dag_file = Path.join(System.tmp_dir!(), "mapped_paging_dag.ex")
    File.write!(dag_file, "# Hello World!")
    on_exit(fn -> File.rm_rf!(dag_file) end)

    dag_def = %Definition{
      name: dag.name,
      mod: MockDagMod,
      task_list: [@task_name],
      stages: [[@task_name]],
      tasks: %{
        @task_name => %{
          upstream: MapSet.new([]),
          downstream: MapSet.new([]),
          map_over: :source,
          store_result: false
        }
      },
      file_path: dag_file
    }

    expect(GustWeb.DAGLoaderMock, :get_definition, 2, fn _dag_id -> {:ok, dag_def} end)

    %{dag: dag, run: run, first: first, second: second, third: third}
  end

  describe "when the expansion is paged" do
    setup do
      Application.put_env(:gust, :mapped_tasks, max_parallel: 2)
    end

    test "shows only the running page and marks it", %{conn: conn} = context do
      view = open_dashboard(conn, context)

      assert visible?(view, context.first)
      assert visible?(view, context.second)
      refute visible?(view, context.third)
      assert has_element?(view, "#mapped-task-page-1[data-running]")
      refute has_element?(view, "#mapped-task-page-2[data-running]")
      assert has_element?(view, "#mapped-task-paging-summary")
    end

    test "keeps the group status when the failure is on another page",
         %{conn: conn} = context do
      {:ok, _task} = Flows.update_task_status(context.third, :failed)

      view = open_dashboard(conn, context)

      refute visible?(view, context.third)
      assert has_element?(view, "#task-status-progress.status-failed")
    end

    test "follows execution to the next page", %{conn: conn} = context do
      view = open_dashboard(conn, context)

      advance_to_second_page(view, context)

      assert visible?(view, context.third)
      refute visible?(view, context.first)
      assert has_element?(view, "#mapped-task-page-2[data-running]")
    end

    test "reacts to an instance on a page that is not displayed", %{conn: conn} = context do
      view = open_dashboard(conn, context)
      view |> element("#mapped-task-page-2") |> render_click()

      {:ok, _task} = Flows.update_task_status(context.second, :failed)
      notify(view, context, context.second)

      assert has_element?(view, "#task-status-progress.status-failed")
    end

    test "stays on a page chosen by the user", %{conn: conn} = context do
      view = open_dashboard(conn, context)

      view |> element("#mapped-task-page-2") |> render_click()
      assert visible?(view, context.third)
      refute visible?(view, context.first)

      notify(view, context, context.second)

      assert visible?(view, context.third)
      refute visible?(view, context.first)
    end

    test "resumes following when the running page is chosen", %{conn: conn} = context do
      view = open_dashboard(conn, context)

      view |> element("#mapped-task-page-2") |> render_click()
      view |> element("#mapped-task-page-1") |> render_click()
      advance_to_second_page(view, context)

      assert visible?(view, context.third)
    end

    test "stays on the page while instances are selected", %{conn: conn} = context do
      view = open_dashboard(conn, context)

      view
      |> element("#mapped-task-selection-form")
      |> render_change(%{"task_ids" => [to_string(context.second.id)]})

      advance_to_second_page(view, context)

      assert visible?(view, context.second)
      refute visible?(view, context.third)
    end

    test "clears the selection when changing page", %{conn: conn} = context do
      view = open_dashboard(conn, context)

      view
      |> element("#mapped-task-selection-form")
      |> render_change(%{"task_ids" => [to_string(context.second.id)]})

      view |> element("#mapped-task-page-2") |> render_click()
      view |> element("#mapped-task-page-1") |> render_click()

      refute has_element?(view, "#mapped-task-select-#{context.second.id}[checked]")
    end

    test "opens the page named in the URL", %{conn: conn} = context do
      view = open_dashboard(conn, context, "&mapped_task_page=2")

      assert visible?(view, context.third)
      refute visible?(view, context.first)
      assert has_element?(view, "#mapped-task-page-2.btn-active[aria-current='page']")
    end

    test "falls back to the first page for an invalid URL page", %{conn: conn} = context do
      view = open_dashboard(conn, context, "&mapped_task_page=abc")

      assert visible?(view, context.first)
      assert has_element?(view, "#mapped-task-page-1.btn-active[aria-current='page']")
    end

    test "applies the status filter named in the URL", %{conn: conn} = context do
      view = open_dashboard(conn, context, "&mapped_task_status=created")

      assert visible?(view, context.third)
      refute visible?(view, context.first)
    end

    test "writes the chosen page to the URL", %{conn: conn} = context do
      view = open_dashboard(conn, context)

      view |> element("#mapped-task-page-2") |> render_click()

      assert assert_patch(view) =~ "mapped_task_page=2"
    end

    test "removes the page from the URL when following again", %{conn: conn} = context do
      view = open_dashboard(conn, context, "&mapped_task_page=2")

      view |> element("#mapped-task-page-1") |> render_click()

      refute assert_patch(view) =~ "mapped_task_page"
    end

    test "writes the status filter to the URL and drops the page", %{conn: conn} = context do
      view = open_dashboard(conn, context, "&mapped_task_page=2")

      view |> element("#mapped-task-status-filter") |> render_change(%{"status" => "created"})

      path = assert_patch(view)
      assert path =~ "mapped_task_status=created"
      refute path =~ "mapped_task_page"
    end

    test "filters across every page", %{conn: conn} = context do
      view = open_dashboard(conn, context)

      view |> element("#mapped-task-status-filter") |> render_change(%{"status" => "created"})

      assert visible?(view, context.third)
      refute visible?(view, context.first)
      refute has_element?(view, "#mapped-task-paging-summary")
      refute has_element?(view, "[data-running]")
    end
  end

  test "lists every instance without a pager within the limit", %{conn: conn} = context do
    Application.put_env(:gust, :mapped_tasks, max_parallel: 3)

    view = open_dashboard(conn, context)

    assert visible?(view, context.first)
    assert visible?(view, context.second)
    assert visible?(view, context.third)
    refute has_element?(view, "#mapped-task-pagination")
    refute has_element?(view, "#mapped-task-paging-summary")
  end

  defp advance_to_second_page(view, context) do
    {:ok, _task} = Flows.update_task_status(context.second, :succeeded)
    {:ok, _task} = Flows.update_task_status(context.third, :running)

    notify(view, context, context.third)
  end

  defp notify(view, context, task) do
    send(
      view.pid,
      {:dag, :run_status, %{run_id: context.run.id, status: :running, task_id: task.id}}
    )
  end

  defp visible?(view, task), do: has_element?(view, "#mapped-task-run-#{task.id}")

  defp open_dashboard(conn, %{dag: dag, run: run}, query \\ "") do
    {:ok, view, _html} =
      live(
        conn,
        ~g"/dags/#{dag.name}/dashboard?run_id=#{run.id}&task_name=#{@task_name}" <> query
      )

    view
  end
end
