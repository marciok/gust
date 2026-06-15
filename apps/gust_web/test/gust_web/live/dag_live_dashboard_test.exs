defmodule GustWeb.DagLiveDashboardTest do
  alias Gust.DAG.Definition
  alias Gust.Flows
  alias GustWeb.DagLive.Dashboard
  use GustWeb.ConnCase

  import Phoenix.LiveViewTest
  import Gust.FlowsFixtures
  import Mox

  setup :verify_on_exit!

  @mock_mod MockDagMod
  @schedule_option "* * * * *"
  @code """
    # Hello World!
  """
  @other_task "other_task"
  @tasks %{
    "sum_41" => %{
      upstream: MapSet.new(["bye"]),
      downstream: MapSet.new([@other_task])
    }
  }

  describe "Index" do
    setup %{conn: conn} do
      dag_name = "my_valid_dag"
      dag = dag_fixture(%{name: dag_name})
      dag_id = dag.id
      run = run_fixture(%{dag_id: dag_id})
      task_name = "sum_41"

      task =
        task_fixture(%{
          run_id: run.id,
          name: task_name,
          inserted_at: ~U[2024-11-07 19:03:37Z],
          updated_at: ~U[2024-11-07 19:03:37Z]
        })

      dag_folder = System.tmp_dir!()
      dag_file = "#{dag_folder}/show_dag_code.ex"

      File.write!(dag_file, @code)

      dag_def = %Definition{
        name: dag_name,
        mod: MockDagMod,
        task_list: [task.name, @other_task],
        stages: [[task.name]],
        tasks: @tasks,
        options: [schedule: @schedule_option],
        file_path: dag_file
      }

      GustWeb.DAGLoaderMock
      |> expect(:get_definition, 2, fn ^dag_id ->
        {:ok, dag_def}
      end)

      on_exit(fn -> File.rm_rf!(dag_file) end)

      %{conn: conn, dag: dag, run: run, task: task, dag_def: dag_def, dag_file: dag_file}
    end

    test "runs styles", %{
      conn: conn,
      dag: dag,
      run: run,
      task: task
    } do
      {:ok, _} = Gust.Flows.update_run_status(run, :running)
      {:ok, _} = Gust.Flows.update_task_status(task, :running)

      base = [{:running, :running, run, task}]

      scenarios = [
        {:failed, :failed},
        {:enqueued, :enqueued},
        {:succeeded, :succeeded},
        {:created, :created},
        {:running, :upstream_failed}
      ]

      entries =
        Enum.reduce(scenarios, base, fn {run_status, task_status}, acc ->
          r = run_fixture(%{dag_id: dag.id, status: run_status})
          t = task_fixture(%{run_id: r.id, status: task_status, name: task.name})
          [{run_status, task_status, r, t} | acc]
        end)
        |> Enum.reverse()

      {:ok, dashboard_live, html} = live(conn, ~g"/dags/#{dag.name}/dashboard")

      assert html =~ dag.name

      Enum.each(entries, fn {run_status, task_status, r, t} ->
        assert has_element?(dashboard_live, "##{t.name}-at-run-#{r.id}.status-#{task_status}")
        assert has_element?(dashboard_live, "#run-status-cell-#{r.id}.status-#{run_status}")
      end)
    end

    def assert_status_badge(status, badge, %{
          conn: conn,
          dag: dag,
          run: run,
          task: task
        }) do
      Flows.update_task_status(task, status)

      {:ok, live, _html} =
        live(conn, ~g"/dags/#{dag.name}/dashboard?run_id=#{run.id}&task_name=#{task.name}")

      badge_html =
        live
        |> element("[data-testid='status-badge']")
        |> render()

      assert badge_html =~ badge
      assert badge_html =~ to_string(status)
    end

    test "renders status badge for a succeeded task", setup do
      assert_status_badge(:succeeded, "badge-success", setup)
    end

    test "renders status badge for a failed task", setup do
      assert_status_badge(:failed, "badge-error", setup)
    end

    test "renders status badge for an upstream_failed task", setup do
      assert_status_badge(:upstream_failed, "badge-warning", setup)
    end

    test "renders status badge for a skipped task", setup do
      assert_status_badge(:skipped, "badge-warning", setup)
    end

    test "renders status badge for a created task", setup do
      assert_status_badge(:created, "badge-info", setup)
    end

    test "renders status badge for a retrying task", setup do
      assert_status_badge(:retrying, "badge-info", setup)
    end

    test "renders status badge for a running task", setup do
      assert_status_badge(:running, "badge-info", setup)
    end

    test "error on dag definition", %{
      conn: conn,
      dag: dag,
      run: run,
      task: task
    } do
      result = %{"less_than_jake" => "Sleep It Off"}
      Flows.update_task_result(task, result)

      live(conn, ~g"/dags/#{dag.name}/dashboard?run_id=#{run.id}&task_name=#{task.name}")

      GustWeb.DAGLoaderMock
      |> expect(:get_definition, fn _dag_id ->
        {:error, {}}
      end)

      assert {:error,
              {:live_redirect,
               %{to: "/dags", flash: %{"warning" => "Syntax error! on my_valid_dag"}}}} =
               live(conn, ~g"/dags/#{dag.name}/dashboard?run_id=#{run.id}&task_name=#{task.name}")
    end

    test "clicking run-status-cell navigates to run details", %{
      conn: conn,
      dag: dag,
      run: run
    } do
      {:ok, dashboard_live, _html} = live(conn, ~g"/dags/#{dag.name}/dashboard")

      run_id = run.id

      dashboard_live
      |> element("#runs-#{run_id} a[href='/dags/#{dag.name}/dashboard?run_id=#{run_id}&page=1']")
      |> render_click()

      assert_redirect dashboard_live, ~g"/dags/#{dag.name}/dashboard?run_id=#{run_id}&page=1", 30
    end

    test "run details", %{
      conn: conn,
      dag: dag,
      run: run
    } do
      run_id = run.id
      {:ok, dashboard_live, _html} = live(conn, ~g"/dags/#{dag.name}/dashboard?run_id=#{run_id}")

      assert has_element?(dashboard_live, ".breadcrumbs")
      assert render(element(dashboard_live, "#selected-item")) =~ "Selected Run #{run.id}"
      assert render(element(dashboard_live, "#selected-item")) =~ "ID #{run.id}"
    end

    test "display task logs", %{
      conn: conn,
      dag: dag,
      run: run,
      task: task
    } do
      log_content = "hello from log"
      log = log_fixture(%{task_id: task.id, content: log_content, level: "info", attempt: 1})

      log_debug =
        log_fixture(%{task_id: task.id, content: log_content, level: "debug", attempt: 1})

      log_warn = log_fixture(%{task_id: task.id, content: log_content, level: "warn", attempt: 1})

      log_error =
        log_fixture(%{task_id: task.id, content: log_content, level: "error", attempt: 1})

      {:ok, dashboard_live, _html} =
        live(conn, ~g"/dags/#{dag.name}/dashboard?run_id=#{run.id}&task_name=#{task.name}")

      log_html = dashboard_live |> element("#log-list") |> render()
      info_log_level = dashboard_live |> element("#logs-#{log.id}") |> render()

      warn_log_level = dashboard_live |> element("#logs-#{log_warn.id}") |> render()
      debug_log_level = dashboard_live |> element("#logs-#{log_debug.id}") |> render()

      error_log_level =
        dashboard_live |> element("#logs-#{log_error.id}") |> render()

      assert log_html =~ log.content
      assert debug_log_level =~ "badge-info"
      assert info_log_level =~ "badge-info"
      assert warn_log_level =~ "badge-warning"
      assert error_log_level =~ "badge-error"

      refute dashboard_live
             |> element("#log-filter")
             |> render_change(%{"_target" => "level", "level" => "info"}) =~ "badge-warning"

      assert dashboard_live
             |> element("#log-filter")
             |> render_change(%{"_target" => "level", "level" => ""}) =~ "badge-warning"
    end

    test "click on non-existent task", %{
      conn: conn,
      dag: dag,
      run: run,
      task: task
    } do
      empty_task_name = @other_task

      {:ok, dashboard_live, _html} =
        live(conn, ~g"/dags/#{dag.name}/dashboard")

      assert dashboard_live
             |> element("[data-testid='#{task.name}-at-run-#{run.id}-link']")
             |> has_element?()

      refute dashboard_live
             |> element("[data-testid='#{empty_task_name}-at-run-#{run.id}-link']")
             |> has_element?()
    end

    test "display selected run", %{
      conn: conn,
      dag: dag,
      run: run
    } do
      {:ok, dashboard_live, _html} =
        live(conn, ~g"/dags/#{dag.name}/dashboard?run_id=#{run.id}")

      assert dashboard_live
             |> element("#runs-#{run.id}.selected-run")
             |> has_element?()
    end

    test "display selected task", %{
      conn: conn,
      dag: dag,
      run: run,
      task: task
    } do
      other_task_same_run = task_fixture(%{run_id: run.id, name: @other_task})
      other_run = run_fixture(%{dag_id: dag.id})
      other_task_other_run = task_fixture(%{run_id: other_run.id, name: @other_task})
      short_format = Application.get_env(:gust_web, :display_date_format)[:short]

      {:ok, dashboard_live, _html} =
        live(conn, ~g"/dags/#{dag.name}/dashboard?run_id=#{run.id}&task_name=#{task.name}")

      assert dashboard_live |> element("#inserted-at") |> render() =~
               Calendar.strftime(task.inserted_at, short_format)

      assert dashboard_live |> element("#updated-at") |> render() =~
               Calendar.strftime(task.updated_at, short_format)

      assert render(element(dashboard_live, "#selected-item")) =~ "Selected #{task.name}"
      assert render(element(dashboard_live, "#selected-item")) =~ "ID #{task.id}"

      assert dashboard_live
             |> element("##{task.name}-at-run-#{run.id}.selected")
             |> has_element?()

      refute dashboard_live
             |> element("##{other_task_same_run.name}-at-run-#{run.id}.selected")
             |> has_element?()

      refute dashboard_live
             |> element("##{other_task_other_run.name}-at-run-#{other_run.id}.selected")
             |> has_element?()
    end

    test "displays the task instances table when a task name has multiple map indexes", %{
      conn: conn,
      dag: dag,
      run: run,
      task: task
    } do
      {:ok, task} = Flows.update_task_mapping(task, 0, %{})

      mapped_task =
        task_fixture(%{
          run_id: run.id,
          name: task.name,
          map_index: 1
        })

      {:ok, dashboard_live, _html} =
        live(conn, ~g"/dags/#{dag.name}/dashboard?run_id=#{run.id}&task_name=#{task.name}")

      assert has_element?(dashboard_live, "#mapped-task-runs")
      assert has_element?(dashboard_live, "#mapped-task-run-#{task.id}")
      assert has_element?(dashboard_live, "#mapped-task-run-#{mapped_task.id}")
    end

    test "display task result", %{
      conn: conn,
      dag: dag,
      run: run,
      task: task
    } do
      result = %{"less_than_jake" => "Sleep It Off"}
      Flows.update_task_result(task, result)

      {:ok, dashboard_live, _html} =
        live(conn, ~g"/dags/#{dag.name}/dashboard?run_id=#{run.id}&task_name=#{task.name}")

      task_result_html = render(element(dashboard_live, "#task-result"))
      refute dashboard_live |> element("#task-error") |> has_element?()
      assert task_result_html =~ result |> Map.values() |> Enum.join()
      assert task_result_html =~ result |> Map.keys() |> Enum.join()
    end

    test "display task error", %{
      conn: conn,
      dag: dag,
      run: run,
      task: task
    } do
      error_msg = "ops..."

      error = %{
        type: :id,
        value: "say_hi",
        message: error_msg
      }

      Flows.update_task_error(task, error)

      {:ok, dashboard_live, _html} =
        live(conn, ~g"/dags/#{dag.name}/dashboard?run_id=#{run.id}&task_name=#{task.name}")

      task_error_html = element(dashboard_live, "#task-error") |> render()

      assert task_error_html =~ error[:value]
      assert task_error_html =~ error_msg
    end

    test "display mermaid chart", %{
      conn: conn,
      dag: dag,
      run: run,
      task: task
    } do
      {:ok, _run} = Gust.Flows.update_run_status(run, :running)
      {:ok, _task} = Gust.Flows.update_task_status(task, :running)
      {:ok, dashboard_live, _html} = live(conn, ~g"/dags/#{dag.name}/dashboard")

      mermaid_html = render(element(dashboard_live, "#mermaid-chart"))
      assert mermaid_html =~ GustWeb.Mermaid.chart(@tasks) |> String.replace("-->", "--&gt;")
    end

    test "display dag code", %{
      conn: conn,
      dag: dag,
      run: run,
      task: task
    } do
      {:ok, _run} = Gust.Flows.update_run_status(run, :running)
      {:ok, _task} = Gust.Flows.update_task_status(task, :running)
      {:ok, dashboard_live, html} = live(conn, ~g"/dags/#{dag.name}/dashboard")

      assert has_element?(dashboard_live, "#code-highlight")
      assert html =~ @code
    end

    test "dag has schedule", %{
      conn: conn,
      dag: dag,
      run: run,
      task: task
    } do
      {:ok, _run} = Gust.Flows.update_run_status(run, :running)
      {:ok, _task} = Gust.Flows.update_task_status(task, :running)
      {:ok, _dashboard_live, html} = live(conn, ~g"/dags/#{dag.name}/dashboard")

      assert html =~ @schedule_option
    end

    test "run is updated", %{
      conn: conn,
      dag: dag,
      run: run,
      task: task
    } do
      {:ok, run} = Gust.Flows.update_run_status(run, :running)
      {:ok, _task} = Gust.Flows.update_task_status(task, :running)
      {:ok, dashboard_live, _html} = live(conn, ~g"/dags/#{dag.name}/dashboard")

      Flows.update_run_status(run, :succeeded)

      Gust.PubSub.broadcast_run_status(run.id, :succeeded)

      assert has_element?(dashboard_live, "#run-status-cell-#{run.id}.status-succeeded")
    end

    test "selected run details are reloaded when its status changes", %{
      conn: conn,
      dag: dag,
      run: run
    } do
      {:ok, dashboard_live, _html} =
        live(conn, ~g"/dags/#{dag.name}/dashboard?run_id=#{run.id}")

      {:ok, _run} = Flows.update_run_status(run, :succeeded)
      Gust.PubSub.broadcast_run_status(run.id, :succeeded)

      assert render(element(dashboard_live, "[data-testid='status-badge']")) =~ "succeeded"
    end

    test "ignores task detail reload for an unrelated task", %{
      conn: conn,
      dag: dag,
      run: run,
      task: task
    } do
      other_task = task_fixture(%{run_id: run.id, name: @other_task})

      {:ok, dashboard_live, _html} =
        live(conn, ~g"/dags/#{dag.name}/dashboard?run_id=#{run.id}&task_name=#{task.name}")

      {:ok, _other_task} = Flows.update_task_status(other_task, :succeeded)

      send(
        dashboard_live.pid,
        {:dag, :run_status, %{run_id: run.id, status: :succeeded, task_id: other_task.id}}
      )

      assert render(element(dashboard_live, "[data-testid='status-badge']")) =~ "created"
    end

    test "log is created", %{
      conn: conn,
      dag: dag,
      run: run,
      task: task
    } do
      log_content = "hello from log"

      {:ok, dashboard_live, _html} =
        live(conn, ~g"/dags/#{dag.name}/dashboard?run_id=#{run.id}&task_name=#{task.name}")

      log = log_fixture(%{task_id: task.id, content: log_content, level: "info", attempt: 1})

      Gust.PubSub.broadcast_log(task.id, log.id)

      log_html = dashboard_live |> element("#log-list") |> render()
      assert log_html =~ log.content
    end

    test "ignores a log event for a task other than the selected task", %{
      conn: conn,
      dag: dag,
      run: run,
      task: task
    } do
      other_task = task_fixture(%{run_id: run.id, name: @other_task})

      log =
        log_fixture(%{
          task_id: other_task.id,
          content: "unrelated task log",
          level: "info",
          attempt: 1
        })

      {:ok, dashboard_live, _html} =
        live(conn, ~g"/dags/#{dag.name}/dashboard?run_id=#{run.id}&task_name=#{task.name}")

      send(
        dashboard_live.pid,
        {:task, :log, %{task_id: other_task.id, log_id: log.id}}
      )

      refute has_element?(dashboard_live, "#logs-#{log.id}")
      refute render(element(dashboard_live, "#log-list")) =~ log.content
    end

    test "dag run started", %{
      conn: conn,
      dag: dag,
      run: run,
      task: task
    } do
      {:ok, _run} = Gust.Flows.update_run_status(run, :running)
      {:ok, _task} = Gust.Flows.update_task_status(task, :running)
      {:ok, dashboard_live, _html} = live(conn, ~g"/dags/#{dag.name}/dashboard")

      new_run = run_fixture(%{dag_id: dag.id})
      Gust.PubSub.broadcast_run_started(dag.id, new_run.id)

      assert dashboard_live |> has_element?("#run-status-cell-#{new_run.id}.status-created")
    end

    test "dag file is updated unsucessfully", %{
      conn: conn,
      dag: dag,
      run: run,
      task: task
    } do
      {:ok, _run} = Gust.Flows.update_run_status(run, :running)
      {:ok, _task} = Gust.Flows.update_task_status(task, :running)
      {:ok, dashboard_live, _html} = live(conn, ~g"/dags/#{dag.name}/dashboard")

      error_msg = "Syntax erro!"
      error = {[], error_msg, ""}
      Gust.PubSub.broadcast_file_update(dag.name, {:error, error}, "reload")

      code_html = render(element(dashboard_live, "#compilation-error"))
      assert code_html =~ error_msg

      reload_time_html = render(element(dashboard_live, "#reload-time"))
      assert reload_time_html =~ ~r/\d{2}:\d{2}:\d{2} \d{2}\/\d{2}/
    end

    test "dag file is updated sucessfully", %{
      conn: conn,
      dag: dag,
      run: run,
      task: task,
      dag_file: dag_file
    } do
      {:ok, _run} = Gust.Flows.update_run_status(run, :running)
      {:ok, _task} = Gust.Flows.update_task_status(task, :running)
      {:ok, dashboard_live, _html} = live(conn, ~g"/dags/#{dag.name}/dashboard")

      updated_code = "Goodbye!"

      File.write!(dag_file, updated_code)
      new_tasks = %{new_task: %{upstream: MapSet.new(["new_tchau"])}}
      bd = System.tmp_dir!()
      File.write("#{bd}/test_new_fs.ex", updated_code)

      dag_def = %Definition{
        mod: @mock_mod,
        task_list: [task.name],
        tasks: new_tasks,
        stages: [[task.name]],
        file_path: "#{bd}/test_new_fs.ex"
      }

      Gust.PubSub.broadcast_file_update(dag.name, {:ok, dag_def}, "reload")

      mermaid_html = render(element(dashboard_live, "#mermaid-chart"))
      assert mermaid_html =~ GustWeb.Mermaid.chart(new_tasks) |> String.replace("-->", "--&gt;")

      code_html = render(element(dashboard_live, "#code-highlight"))
      assert code_html =~ updated_code

      assert has_element?(dashboard_live, "#reload-time")

      reload_time_html = render(element(dashboard_live, "#reload-time"))
      assert reload_time_html =~ ~r/\d{2}:\d{2}:\d{2} \d{2}\/\d{2}/
    end

    test "click on cancel on running", %{
      conn: conn,
      dag: dag,
      run: run,
      task: task
    } do
      {:ok, running_task} = Gust.Flows.update_task_status(task, :running)

      {:ok, dashboard_live, _html} =
        live(
          conn,
          ~g"/dags/#{dag.name}/dashboard?run_id=#{run.id}&task_name=#{running_task.name}"
        )

      previous_dag_adapter = Application.get_env(:gust, :dag_adapter)

      on_exit(fn ->
        Application.put_env(:gust, :dag_adapter, previous_dag_adapter)
      end)

      Application.put_env(:gust, :dag_adapter, elixir: %{runtime: Gust.RuntimeAdapterMock})
      runtime = Gust.RuntimeAdapterMock

      GustWeb.DAGTerminatorMock
      |> expect(:kill_task, fn ^running_task, :cancelled, ^runtime -> nil end)

      assert dashboard_live |> element("#cancel-task") |> render_click() =~
               "Task: #{running_task.name} was cancelled"

      refute has_element?(dashboard_live, "#cancel-task[disabled]")

      {:ok, _failed_task} = Gust.Flows.update_task_status(running_task, :failed)
      Gust.PubSub.broadcast_run_status(run.id, :failed, running_task.id)

      refute has_element?(dashboard_live, "#cancel-task")

      assert has_element?(
               dashboard_live,
               "##{running_task.name}-at-run-#{run.id}.status-failed"
             )

      assert render(element(dashboard_live, "[data-testid='status-badge']")) =~ "failed"
    end

    test "click on all runs", %{
      conn: conn,
      dag: dag
    } do
      {:ok, dashboard_live, _html} =
        live(conn, ~g"/dags/#{dag.name}/dashboard")

      dashboard_live |> element("#all-runs") |> render_click()

      assert_redirect dashboard_live, ~g"/dags/#{dag.name}/runs?page_size=30&page=1"
    end

    test "click on next page", %{
      conn: conn,
      dag: dag
    } do
      {:ok, dashboard_live, _html} =
        live(conn, ~g"/dags/#{dag.name}/dashboard")

      dashboard_live |> element("#next-page") |> render_click()

      assert_redirect dashboard_live, ~g"/dags/#{dag.name}/dashboard?page=2"
    end

    test "click on prev page when page is 1", %{
      conn: conn,
      dag: dag
    } do
      {:ok, dashboard_live, _html} =
        live(conn, ~g"/dags/#{dag.name}/dashboard")

      dashboard_live |> element("#prev-page") |> render_click()

      assert_redirect dashboard_live, ~g"/dags/#{dag.name}/dashboard?page=1"
    end

    test "click on prev page when page is pargen than 1", %{
      conn: conn,
      dag: dag
    } do
      {:ok, dashboard_live, _html} =
        live(conn, ~g"/dags/#{dag.name}/dashboard?page=2")

      dashboard_live |> element("#prev-page") |> render_click()

      assert_redirect dashboard_live, ~g"/dags/#{dag.name}/dashboard?page=1"
    end

    test "invalid page falls back to the first page", %{
      conn: conn,
      dag: dag
    } do
      {:ok, dashboard_live, _html} =
        live(conn, ~g"/dags/#{dag.name}/dashboard?page=invalid")

      assert has_element?(
               dashboard_live,
               "#next-page[href='/dags/#{dag.name}/dashboard?page=2']"
             )

      assert has_element?(
               dashboard_live,
               "#prev-page[href='/dags/#{dag.name}/dashboard?page=1']"
             )
    end

    test "unknown task selection renders without a selected item", %{
      conn: conn,
      dag: dag,
      run: run
    } do
      {:ok, dashboard_live, _html} =
        live(
          conn,
          ~g"/dags/#{dag.name}/dashboard?run_id=#{run.id}&task_name=missing-task"
        )

      refute has_element?(dashboard_live, "#selected-item")
    end

    test "stale cancel event does not crash for a task that is no longer running", %{
      conn: conn,
      dag: dag,
      run: run,
      task: task
    } do
      {:ok, dashboard_live, _html} =
        live(conn, ~g"/dags/#{dag.name}/dashboard?run_id=#{run.id}&task_name=#{task.name}")

      assert render_click(dashboard_live, "cancel_task", %{"id" => task.id}) =~
               "Task: #{task.name} is not running"
    end

    test "selected task receives status updates when its run is outside the current page", %{
      conn: conn,
      dag: dag,
      run: run,
      task: task
    } do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      for seconds <- 1..30 do
        run_fixture(%{
          dag_id: dag.id,
          inserted_at: DateTime.add(now, seconds, :second)
        })
      end

      {:ok, dashboard_live, _html} =
        live(conn, ~g"/dags/#{dag.name}/dashboard?run_id=#{run.id}&task_name=#{task.name}")

      refute has_element?(dashboard_live, "#run-status-cell-#{run.id}")

      {:ok, _task} = Flows.update_task_status(task, :succeeded)
      Gust.PubSub.broadcast_run_status(run.id, :succeeded, task.id)

      assert render(element(dashboard_live, "[data-testid='status-badge']")) =~ "succeeded"
    end

    test "click on cancel on retrying", %{
      conn: conn,
      dag: dag,
      run: run,
      task: task
    } do
      {:ok, running_task} = Gust.Flows.update_task_status(task, :retrying)

      {:ok, dashboard_live, _html} =
        live(
          conn,
          ~g"/dags/#{dag.name}/dashboard?run_id=#{run.id}&task_name=#{running_task.name}"
        )

      GustWeb.DAGTerminatorMock
      |> expect(:cancel_timer, fn ^running_task, :cancelled -> nil end)

      assert dashboard_live |> element("#cancel-task") |> render_click() =~
               "Task: #{running_task.name} retrying cancelled"

      refute has_element?(dashboard_live, "#cancel-task[disabled]")
    end

    test "click restart run on succeeded run", %{
      conn: conn,
      dag: dag,
      run: run
    } do
      {:ok, failed_run} = Gust.Flows.update_run_status(run, :succeeded)

      GustWeb.DAGRunTriggerMock
      |> expect(:reset_run, fn %Flows.Run{id: run_id, status: :succeeded} ->
        assert run_id == failed_run.id
        run
      end)

      {:ok, dashboard_live, _html} =
        live(conn, ~g"/dags/#{dag.name}/dashboard?run_id=#{failed_run.id}")

      assert dashboard_live |> element("#restart") |> render_click() =~
               "Run: #{failed_run.id} was restarted"
    end

    test "click restart task on succeeded task", %{
      conn: conn,
      dag: dag,
      run: run,
      task: task
    } do
      {:ok, succeeded_task} = Gust.Flows.update_task_status(task, :succeeded)

      GustWeb.DAGRunTriggerMock
      |> expect(:reset_task, fn _tasks, ^succeeded_task, nil -> run end)

      {:ok, dashboard_live, _html} =
        live(
          conn,
          ~g"/dags/#{dag.name}/dashboard?run_id=#{run.id}&task_name=#{succeeded_task.name}"
        )

      assert dashboard_live |> element("#restart") |> render_click() =~
               "Task: #{succeeded_task.name} was restarted"
    end

    test "click restart task on running task", %{
      conn: conn,
      dag: dag,
      run: run,
      task: task
    } do
      {:ok, dashboard_live, _html} =
        live(conn, ~g"/dags/#{dag.name}/dashboard?run_id=#{run.id}&task_name=#{task.name}")

      refute dashboard_live |> has_element?("#restart")
    end

    test "no cancel button for created run", %{
      conn: conn,
      dag: dag,
      run: run
    } do
      {:ok, dashboard_live, _html} =
        live(conn, ~g"/dags/#{dag.name}/dashboard?run_id=#{run.id}")

      refute dashboard_live |> has_element?("#restart")
    end

    test "no cancel button for not running task", %{
      conn: conn,
      dag: dag,
      run: run,
      task: task
    } do
      {:ok, dashboard_live, _html} =
        live(conn, ~g"/dags/#{dag.name}/dashboard?run_id=#{run.id}&task_name=#{task.name}")

      refute dashboard_live |> has_element?("#cancel-task")
    end

    test "click on trigger", %{
      conn: conn,
      dag: dag
    } do
      {:ok, dashboard_live, _html} = live(conn, ~g"/dags/#{dag.name}/dashboard")
      dag_id = dag.id

      GustWeb.DAGRunTriggerMock |> expect(:dispatch_run, fn new_run -> new_run end)

      triggered_flash = dashboard_live |> element("#trigger-dag-run-#{dag.id}") |> render_click()
      last_run = Flows.get_dag_with_runs!(dag_id).runs |> List.last()

      assert triggered_flash =~ "Run #{last_run.id} triggered"
    end

    test "display run params when present", %{
      conn: conn,
      dag: dag
    } do
      params = %{"brand" => "ford", "model" => "ranger"}

      run_with_params =
        run_fixture(%{dag_id: dag.id, params: params})

      {:ok, dashboard_live, _html} =
        live(conn, ~g"/dags/#{dag.name}/dashboard?run_id=#{run_with_params.id}")

      assert has_element?(dashboard_live, "#run-params")
      params_html = dashboard_live |> element("#run-params") |> render()
      assert params_html =~ "ford"
      assert params_html =~ "ranger"
    end

    test "hide run params section when params are empty", %{
      conn: conn,
      dag: dag,
      run: run
    } do
      {:ok, dashboard_live, _html} =
        live(conn, ~g"/dags/#{dag.name}/dashboard?run_id=#{run.id}")

      refute has_element?(dashboard_live, "#run-params")
    end
  end

  describe "get_expanded/1" do
    test "returns every mapped task instance with the same name and run" do
      dag = dag_fixture()
      run = run_fixture(%{dag_id: dag.id})
      other_run = run_fixture(%{dag_id: dag.id})
      task_name = "insert_models"

      first = task_fixture(%{run_id: run.id, name: task_name, map_index: 0})
      second = task_fixture(%{run_id: run.id, name: task_name, map_index: 1})
      _other_task = task_fixture(%{run_id: run.id, name: "other_task", map_index: 0})
      _other_run_task = task_fixture(%{run_id: other_run.id, name: task_name, map_index: 0})

      assert Dashboard.get_expanded(first) == [first, second]
      assert Dashboard.get_expanded(%Flows.Task{first | map_index: nil}) == []
    end
  end

  describe "mapped tasks" do
    test "shows map badge and task run list instead of task result", %{conn: conn} do
      dag_name = "mapped_dashboard_dag"
      dag = dag_fixture(%{name: dag_name})
      run = run_fixture(%{dag_id: dag.id})
      task_name = "insert_models"

      task =
        task_fixture(%{
          run_id: run.id,
          name: task_name,
          status: :succeeded,
          map_index: 0,
          result: %{"hidden" => "result"}
        })

      mapped_task =
        task_fixture(%{
          run_id: run.id,
          name: task_name,
          status: :failed,
          map_index: 1,
          result: %{"model" => "b"}
        })

      mapped_log =
        log_fixture(%{task_id: mapped_task.id, content: "mapped log", level: "info", attempt: 1})

      dag_file = Path.join(System.tmp_dir!(), "mapped_dashboard_dag.ex")
      File.write!(dag_file, @code)

      dag_def = %Definition{
        name: dag_name,
        mod: @mock_mod,
        task_list: [task_name],
        stages: [[task_name]],
        tasks: %{
          task_name => %{
            upstream: MapSet.new(["say_by"]),
            downstream: MapSet.new([]),
            map_over: :say_by,
            store_result: false
          }
        },
        file_path: dag_file
      }

      GustWeb.DAGLoaderMock
      |> expect(:get_definition, 4, fn dag_id ->
        assert dag_id == dag.id
        {:ok, dag_def}
      end)

      on_exit(fn -> File.rm_rf!(dag_file) end)

      {:ok, dashboard_live, _html} =
        live(conn, ~g"/dags/#{dag.name}/dashboard?run_id=#{run.id}&task_name=#{task_name}")

      assert render(element(dashboard_live, "##{task_name}-map-badge")) =~ "[]"
      assert has_element?(dashboard_live, "#mapped-task-runs")
      assert has_element?(dashboard_live, "#mapped-task-run-#{task.id}")
      assert has_element?(dashboard_live, "#mapped-task-run-#{mapped_task.id}")
      assert has_element?(dashboard_live, "#show-mapped-task-#{task.id}")
      assert has_element?(dashboard_live, "#show-mapped-task-#{mapped_task.id}")
      refute has_element?(dashboard_live, "#task-result")
      refute has_element?(dashboard_live, "#log-list")

      {:ok, _mapped_task} = Flows.update_task_status(mapped_task, :succeeded)
      Gust.PubSub.broadcast_run_status(run.id, :succeeded, mapped_task.id)

      assert render(element(dashboard_live, "#mapped-task-run-#{mapped_task.id}")) =~
               "succeeded"

      {:ok, mapped_task_live, _html} =
        live(
          conn,
          ~g"/dags/#{dag.name}/dashboard?run_id=#{run.id}&task_name=#{task_name}&task_index=1"
        )

      assert render(element(mapped_task_live, "#task-result")) =~ "model"
      assert render(element(mapped_task_live, "#task-result")) =~ "b"
      assert has_element?(mapped_task_live, "#log-list")
      assert has_element?(mapped_task_live, "#logs-#{mapped_log.id}")
      assert render(element(mapped_task_live, "#dag-run-task-index-link")) =~ "[1]"
      refute has_element?(mapped_task_live, "#mapped-task-runs")
    end

    test "restarts all mapped task instances from the aggregate view", %{conn: conn} do
      dag_name = "mapped_restart_dag"
      dag = dag_fixture(%{name: dag_name})
      run = run_fixture(%{dag_id: dag.id})
      task_name = "insert_models"

      task =
        task_fixture(%{
          run_id: run.id,
          name: task_name,
          status: :succeeded,
          map_index: 0
        })

      _mapped_task =
        task_fixture(%{
          run_id: run.id,
          name: task_name,
          status: :failed,
          map_index: 1
        })

      dag_file = Path.join(System.tmp_dir!(), "mapped_restart_dag.ex")
      File.write!(dag_file, @code)

      dag_def = %Definition{
        name: dag_name,
        mod: @mock_mod,
        task_list: [task_name],
        stages: [[task_name]],
        tasks: %{
          task_name => %{
            upstream: MapSet.new([]),
            downstream: MapSet.new([]),
            map_over: :say_by,
            store_result: false
          }
        },
        file_path: dag_file
      }

      GustWeb.DAGLoaderMock
      |> expect(:get_definition, 2, fn dag_id ->
        assert dag_id == dag.id
        {:ok, dag_def}
      end)

      tasks_graph = dag_def.tasks

      GustWeb.DAGRunTriggerMock
      |> expect(:reset_task, fn ^tasks_graph, ^task, nil -> [] end)

      on_exit(fn -> File.rm_rf!(dag_file) end)

      {:ok, dashboard_live, _html} =
        live(conn, ~g"/dags/#{dag.name}/dashboard?run_id=#{run.id}&task_name=#{task_name}")

      assert dashboard_live |> element("#restart") |> render_click() =~
               "Task: #{task.name} was restarted"
    end

    test "restarts the selected mapped task instance from the indexed view", %{conn: conn} do
      dag_name = "mapped_restart_index_dag"
      dag = dag_fixture(%{name: dag_name})
      run = run_fixture(%{dag_id: dag.id})
      task_name = "insert_models"

      _task =
        task_fixture(%{
          run_id: run.id,
          name: task_name,
          status: :succeeded,
          map_index: 0
        })

      mapped_task =
        task_fixture(%{
          run_id: run.id,
          name: task_name,
          status: :failed,
          map_index: 1
        })

      dag_file = Path.join(System.tmp_dir!(), "mapped_restart_index_dag.ex")
      File.write!(dag_file, @code)

      dag_def = %Definition{
        name: dag_name,
        mod: @mock_mod,
        task_list: [task_name],
        stages: [[task_name]],
        tasks: %{
          task_name => %{
            upstream: MapSet.new([]),
            downstream: MapSet.new([]),
            map_over: :say_by,
            store_result: false
          }
        },
        file_path: dag_file
      }

      GustWeb.DAGLoaderMock
      |> expect(:get_definition, 2, fn dag_id ->
        assert dag_id == dag.id
        {:ok, dag_def}
      end)

      tasks_graph = dag_def.tasks
      mapped_task_id = mapped_task.id

      GustWeb.DAGRunTriggerMock
      |> expect(:reset_task, fn ^tasks_graph, %Flows.Task{id: ^mapped_task_id, map_index: 1}, 1 ->
        []
      end)

      on_exit(fn -> File.rm_rf!(dag_file) end)

      {:ok, dashboard_live, _html} =
        live(
          conn,
          ~g"/dags/#{dag.name}/dashboard?run_id=#{run.id}&task_name=#{task_name}&task_index=1"
        )

      assert dashboard_live |> element("#restart") |> render_click() =~
               "Task: #{mapped_task.name} [1] was restarted"
    end
  end
end
