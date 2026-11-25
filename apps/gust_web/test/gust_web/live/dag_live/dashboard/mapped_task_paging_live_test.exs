defmodule GustWeb.DagLive.Dashboard.MappedTaskPagingLiveTest do
  use GustWeb.ConnCase

  import Gust.FlowsFixtures
  import Mox
  import Phoenix.LiveViewTest

  alias Gust.DAG.Definition
  alias Gust.Flows
  alias GustWeb.DagLive.Dashboard

  setup :verify_on_exit!

  @task_name "insert_models"

  setup do
    previous = Application.fetch_env(:gust_web, :mapped_task_page_size)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:gust_web, :mapped_task_page_size, value)
        :error -> Application.delete_env(:gust_web, :mapped_task_page_size)
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
      Application.put_env(:gust_web, :mapped_task_page_size, 2)
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

    test "stays on the first page while execution moves on", %{conn: conn} = context do
      view = open_dashboard(conn, context)

      advance_to_second_page(view, context)

      assert visible?(view, context.first)
      refute visible?(view, context.third)
      assert has_element?(view, "#mapped-task-page-1.btn-active[aria-current='page']")
      assert has_element?(view, "#mapped-task-page-2[data-running]")
    end

    test "stays on the first page once every instance has finished",
         %{conn: conn} = context do
      view = open_dashboard(conn, context)

      for task <- [context.second, context.third] do
        {:ok, _task} = Flows.update_task_status(task, :succeeded)
        notify(view, context, task)
      end

      assert visible?(view, context.first)
      refute visible?(view, context.third)
      refute has_element?(view, "[data-running]")
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

    test "keeps the clicked page through a burst of queued updates", %{conn: conn} = context do
      previous = Application.fetch_env(:gust_web, :dashboard_refresh_interval)
      Application.put_env(:gust_web, :dashboard_refresh_interval, 60_000)

      on_exit(fn ->
        case previous do
          {:ok, value} -> Application.put_env(:gust_web, :dashboard_refresh_interval, value)
          :error -> Application.delete_env(:gust_web, :dashboard_refresh_interval)
        end
      end)

      view = open_dashboard(conn, context)
      {:ok, _task} = Flows.update_task_status(context.second, :succeeded)

      for _event <- 1..20, do: notify(view, context, context.second)

      view |> element("#mapped-task-page-2") |> render_click()
      assert assert_patch(view) =~ "mapped_task_page=2"

      {:ok, _task} = Flows.update_task_status(context.third, :running)
      for _event <- 1..20, do: notify(view, context, context.third)
      send(view.pid, :flush_run_updates)

      assert has_element?(view, "#mapped-task-page-2.btn-active[aria-current='page']")
      assert has_element?(view, "#mapped-task-run-#{context.third.id} .badge", "running")
      refute visible?(view, context.first)
      refute visible?(view, context.second)
    end

    test "does not resend visible rows when another page changes", %{conn: conn} = context do
      view = open_dashboard(conn, context)
      socket = :sys.get_state(view.pid).socket
      {:ok, _task} = Flows.update_task_status(context.third, :failed)

      {:noreply, socket} =
        Dashboard.handle_info(
          {:dag, :run_status,
           %{run_id: context.run.id, status: :running, task_id: context.third.id}},
          socket
        )

      assert socket.assigns.item_status == :failed
      assert socket.assigns.streams.mapped_tasks.inserts == []
      refute socket.assigns.streams.mapped_tasks.reset?
    end

    test "sends only the changed visible row and preserves selections", %{conn: conn} = context do
      view = open_dashboard(conn, context)
      view |> element("#select-all-mapped-tasks") |> render_click()
      socket = :sys.get_state(view.pid).socket
      {:ok, _task} = Flows.update_task_status(context.second, :succeeded)

      {:noreply, socket} =
        Dashboard.handle_info(
          {:dag, :run_status,
           %{run_id: context.run.id, status: :running, task_id: context.second.id}},
          socket
        )

      assert [insert] = socket.assigns.streams.mapped_tasks.inserts
      assert elem(insert, 0) == "mapped-task-run-#{context.second.id}"
      refute socket.assigns.streams.mapped_tasks.reset?
      assert socket.assigns.selected_task_ids == [context.first.id, context.second.id]

      notify(view, context, context.second)

      assert has_element?(
               view,
               "#mapped-task-run-#{context.second.id} .badge-success",
               "succeeded"
             )

      assert has_element?(view, "#mapped-task-select-#{context.second.id}[checked]")
    end

    test "replaces visible rows when a status update changes filter membership",
         %{conn: conn} = context do
      view = open_dashboard(conn, context, "&mapped_task_status=running")
      assert visible?(view, context.second)

      advance_to_second_page(view, context)

      refute visible?(view, context.second)
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

    test "selects every instance on the displayed page", %{conn: conn} = context do
      view = open_dashboard(conn, context)

      view |> element("#select-all-mapped-tasks") |> render_click()

      assert has_element?(view, "#select-all-mapped-tasks[checked]")
      assert has_element?(view, "#mapped-task-select-#{context.first.id}[checked]")
      assert has_element?(view, "#mapped-task-select-#{context.second.id}[checked]")
      assert has_element?(view, "#selected-mapped-tasks-count", "(2)")
      refute has_element?(view, "#restart[disabled]")
    end

    test "clears the selection when toggled again", %{conn: conn} = context do
      view = open_dashboard(conn, context)

      view |> element("#select-all-mapped-tasks") |> render_click()
      view |> element("#select-all-mapped-tasks") |> render_click()

      refute has_element?(view, "#select-all-mapped-tasks[checked]")
      refute has_element?(view, "#mapped-task-select-#{context.first.id}[checked]")
      refute has_element?(view, "#selected-mapped-tasks-count")
      assert has_element?(view, "#restart[disabled]")
    end

    test "marks all selected once every displayed instance is checked",
         %{conn: conn} = context do
      view = open_dashboard(conn, context)

      view
      |> element("#mapped-task-selection-form")
      |> render_change(%{"task_ids" => [to_string(context.first.id)]})

      refute has_element?(view, "#select-all-mapped-tasks[checked]")

      view
      |> element("#mapped-task-selection-form")
      |> render_change(%{
        "task_ids" => [to_string(context.first.id), to_string(context.second.id)]
      })

      assert has_element?(view, "#select-all-mapped-tasks[checked]")
    end

    test "selects only the instances matching the status filter", %{conn: conn} = context do
      view = open_dashboard(conn, context, "&mapped_task_status=created")

      view |> element("#select-all-mapped-tasks") |> render_click()

      assert has_element?(view, "#mapped-task-select-#{context.third.id}[checked]")
      assert has_element?(view, "#selected-mapped-tasks-count", "(1)")
    end

    test "disables select all when no instance is displayed", %{conn: conn} = context do
      view = open_dashboard(conn, context, "&mapped_task_status=failed")

      assert has_element?(view, "#select-all-mapped-tasks[disabled]")
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

    test "keeps the chosen running page in the URL", %{conn: conn} = context do
      view = open_dashboard(conn, context, "&mapped_task_page=2")

      view |> element("#mapped-task-page-1") |> render_click()

      assert assert_patch(view) =~ "mapped_task_page=1"
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
    Application.put_env(:gust_web, :mapped_task_page_size, 3)

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
