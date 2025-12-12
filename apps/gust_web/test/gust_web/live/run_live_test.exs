defmodule GustWeb.RunLiveTest do
  alias Gust.DAG.Definition
  alias Gust.Flows
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
        {:retrying, :retrying},
        {:running, :upstream_failed}
      ]

      entries =
        Enum.reduce(scenarios, base, fn {run_status, task_status}, acc ->
          r = run_fixture(%{dag_id: dag.id, status: run_status})
          t = task_fixture(%{run_id: r.id, status: task_status, name: task.name})
          [{run_status, task_status, r, t} | acc]
        end)
        |> Enum.reverse()

      {:ok, run_live, html} = live(conn, ~p"/dags/#{dag.name}/runs")

      assert html =~ dag.name

      Enum.each(entries, fn {run_status, task_status, r, t} ->
        assert has_element?(run_live, "##{t.name}-at-run-#{r.id}.status-#{task_status}")
        assert has_element?(run_live, "#run-status-cell-#{r.id}.status-#{run_status}")
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
        live(conn, ~p"/dags/#{dag.name}/runs?run_id=#{run.id}&task_name=#{task.name}")

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

      live(conn, ~p"/dags/#{dag.name}/runs?run_id=#{run.id}&task_name=#{task.name}")

      GustWeb.DAGLoaderMock
      |> expect(:get_definition, fn _dag_id ->
        {:error, {}}
      end)

      assert {:error,
              {:live_redirect,
               %{to: "/dags", flash: %{"warning" => "Syntax error! on my_valid_dag"}}}} =
               live(conn, ~p"/dags/#{dag.name}/runs?run_id=#{run.id}&task_name=#{task.name}")
    end

    test "clicking run-status-cell navigates to run details", %{
      conn: conn,
      dag: dag,
      run: run
    } do
      {:ok, run_live, _html} = live(conn, ~p"/dags/#{dag.name}/runs")

      run_id = run.id

      run_live
      |> element("#runs-#{run_id} a[href='/dags/#{dag.name}/runs?run_id=#{run_id}&page=1']")
      |> render_click()

      assert_redirect run_live, ~p"/dags/#{dag.name}/runs?run_id=#{run_id}&page=1", 30
    end

    test "run details", %{
      conn: conn,
      dag: dag,
      run: run
    } do
      run_id = run.id
      {:ok, run_live, _html} = live(conn, ~p"/dags/#{dag.name}/runs?run_id=#{run_id}")

      assert has_element?(run_live, ".breadcrumbs")
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

      {:ok, run_live, _html} =
        live(conn, ~p"/dags/#{dag.name}/runs?run_id=#{run.id}&task_name=#{task.name}")

      log_html = run_live |> element("#log-list") |> render()
      info_log_level = run_live |> element("#logs-#{log.id}") |> render()

      warn_log_level = run_live |> element("#logs-#{log_warn.id}") |> render()
      debug_log_level = run_live |> element("#logs-#{log_debug.id}") |> render()

      error_log_level =
        run_live |> element("#logs-#{log_error.id}") |> render()

      assert log_html =~ log.content
      assert debug_log_level =~ "badge-info"
      assert info_log_level =~ "badge-info"
      assert warn_log_level =~ "badge-warning"
      assert error_log_level =~ "badge-error"

      refute run_live
             |> element("#log-filter")
             |> render_change(%{"_target" => "level", "level" => "info"}) =~ "badge-warning"

      assert run_live
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

      {:ok, run_live, _html} =
        live(conn, ~p"/dags/#{dag.name}/runs")

      assert run_live
             |> element("[data-testid='#{task.name}-at-run-#{run.id}-link']")
             |> has_element?()

      refute run_live
             |> element("[data-testid='#{empty_task_name}-at-run-#{run.id}-link']")
             |> has_element?()
    end

    test "display selected run", %{
      conn: conn,
      dag: dag,
      run: run
    } do
      {:ok, run_live, _html} =
        live(conn, ~p"/dags/#{dag.name}/runs?run_id=#{run.id}")

      assert run_live
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

      {:ok, run_live, _html} =
        live(conn, ~p"/dags/#{dag.name}/runs?run_id=#{run.id}&task_name=#{task.name}")

      assert run_live |> element("#inserted-at") |> render() =~
               DateTime.to_iso8601(task.inserted_at)

      assert run_live |> element("#updated-at") |> render() =~
               DateTime.to_iso8601(task.updated_at)

      assert run_live
             |> element("##{task.name}-at-run-#{run.id}.selected")
             |> has_element?()

      refute run_live
             |> element("##{other_task_same_run.name}-at-run-#{run.id}.selected")
             |> has_element?()

      refute run_live
             |> element("##{other_task_other_run.name}-at-run-#{other_run.id}.selected")
             |> has_element?()
    end

    test "display task result", %{
      conn: conn,
      dag: dag,
      run: run,
      task: task
    } do
      result = %{"less_than_jake" => "Sleep It Off"}
      Flows.update_task_result(task, result)

      {:ok, run_live, _html} =
        live(conn, ~p"/dags/#{dag.name}/runs?run_id=#{run.id}&task_name=#{task.name}")

      task_result_html = render(element(run_live, "#task-result"))
      refute run_live |> element("#task-error") |> has_element?()
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

      {:ok, run_live, _html} =
        live(conn, ~p"/dags/#{dag.name}/runs?run_id=#{run.id}&task_name=#{task.name}")

      task_error_html = element(run_live, "#task-error") |> render()

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
      {:ok, run_live, _html} = live(conn, ~p"/dags/#{dag.name}/runs")

      mermaid_html = render(element(run_live, "#mermaid-chart"))
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
      {:ok, run_live, html} = live(conn, ~p"/dags/#{dag.name}/runs")

      assert has_element?(run_live, "#code-highlight")
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
      {:ok, _run_live, html} = live(conn, ~p"/dags/#{dag.name}/runs")

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
      {:ok, run_live, _html} = live(conn, ~p"/dags/#{dag.name}/runs")

      Flows.update_run_status(run, :succeeded)

      Gust.PubSub.broadcast_run_status(run.id, :succeeded)

      assert has_element?(run_live, "#run-status-cell-#{run.id}.status-succeeded")
    end

    test "log is created", %{
      conn: conn,
      dag: dag,
      run: run,
      task: task
    } do
      log_content = "hello from log"

      {:ok, run_live, _html} =
        live(conn, ~p"/dags/#{dag.name}/runs?run_id=#{run.id}&task_name=#{task.name}")

      log = log_fixture(%{task_id: task.id, content: log_content, level: "info", attempt: 1})

      Gust.PubSub.broadcast_log(task.id, log.id)

      log_html = run_live |> element("#log-list") |> render()
      assert log_html =~ log.content
    end

    test "dag run started", %{
      conn: conn,
      dag: dag,
      run: run,
      task: task
    } do
      {:ok, _run} = Gust.Flows.update_run_status(run, :running)
      {:ok, _task} = Gust.Flows.update_task_status(task, :running)
      {:ok, run_live, _html} = live(conn, ~p"/dags/#{dag.name}/runs")

      new_run = run_fixture(%{dag_id: dag.id})
      Gust.PubSub.broadcast_run_started(dag.id, new_run.id)

      assert run_live |> has_element?("#run-status-cell-#{new_run.id}.status-created")
    end

    test "dag file is updated unsucessfully", %{
      conn: conn,
      dag: dag,
      run: run,
      task: task
    } do
      {:ok, _run} = Gust.Flows.update_run_status(run, :running)
      {:ok, _task} = Gust.Flows.update_task_status(task, :running)
      {:ok, run_live, _html} = live(conn, ~p"/dags/#{dag.name}/runs")

      error_msg = "Syntax erro!"
      error = {[], error_msg, ""}
      Gust.PubSub.broadcast_file_update(dag.name, {:error, error}, "reload")

      code_html = render(element(run_live, "#compilation-error"))
      assert code_html =~ error_msg

      reload_time_html = render(element(run_live, "#reload-time"))
      assert reload_time_html =~ ~r/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z/
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
      {:ok, run_live, _html} = live(conn, ~p"/dags/#{dag.name}/runs")

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

      mermaid_html = render(element(run_live, "#mermaid-chart"))
      assert mermaid_html =~ GustWeb.Mermaid.chart(new_tasks) |> String.replace("-->", "--&gt;")

      code_html = render(element(run_live, "#code-highlight"))
      assert code_html =~ updated_code

      assert has_element?(run_live, "#reload-time")

      reload_time_html = render(element(run_live, "#reload-time"))
      assert reload_time_html =~ ~r/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z/
    end

    test "click on cancel on running", %{
      conn: conn,
      dag: dag,
      run: run,
      task: task
    } do
      {:ok, running_task} = Gust.Flows.update_task_status(task, :running)

      {:ok, run_live, _html} =
        live(conn, ~p"/dags/#{dag.name}/runs?run_id=#{run.id}&task_name=#{running_task.name}")

      GustWeb.DAGTerminatorMock
      |> expect(:kill_task, fn ^running_task, :cancelled -> nil end)

      assert run_live |> element("#cancel-task") |> render_click() =~
               "Task: #{running_task.name} was cancelled"
    end

    test "click on next page", %{
      conn: conn,
      dag: dag
    } do
      {:ok, run_live, _html} =
        live(conn, ~p"/dags/#{dag.name}/runs")

      run_live |> element("#next-page") |> render_click()

      assert_redirect run_live, ~p"/dags/#{dag.name}/runs?page=2"
    end

    test "click on prev page when page is 1", %{
      conn: conn,
      dag: dag
    } do
      {:ok, run_live, _html} =
        live(conn, ~p"/dags/#{dag.name}/runs")

      run_live |> element("#prev-page") |> render_click()

      assert_redirect run_live, ~p"/dags/#{dag.name}/runs?page=1"
    end

    test "click on prev page when page is pargen than 1", %{
      conn: conn,
      dag: dag
    } do
      {:ok, run_live, _html} =
        live(conn, ~p"/dags/#{dag.name}/runs?page=2")

      run_live |> element("#prev-page") |> render_click()

      assert_redirect run_live, ~p"/dags/#{dag.name}/runs?page=1"
    end

    test "click on cancel on retrying", %{
      conn: conn,
      dag: dag,
      run: run,
      task: task
    } do
      {:ok, running_task} = Gust.Flows.update_task_status(task, :retrying)

      {:ok, run_live, _html} =
        live(conn, ~p"/dags/#{dag.name}/runs?run_id=#{run.id}&task_name=#{running_task.name}")

      GustWeb.DAGTerminatorMock
      |> expect(:cancel_timer, fn ^running_task, :cancelled -> nil end)

      assert run_live |> element("#cancel-task") |> render_click() =~
               "Task: #{running_task.name} retrying cancelled"
    end

    test "click restart run on succeeded run", %{
      conn: conn,
      dag: dag,
      run: run
    } do
      {:ok, failed_run} = Gust.Flows.update_run_status(run, :succeeded)

      GustWeb.DAGRunRestarterMock |> expect(:restart_run, fn ^failed_run -> nil end)

      {:ok, run_live, _html} =
        live(conn, ~p"/dags/#{dag.name}/runs?run_id=#{failed_run.id}")

      assert run_live |> element("#restart-run") |> render_click() =~
               "Run: #{failed_run.id} was restarted"
    end

    test "click restart run on failed run", %{
      conn: conn,
      dag: dag,
      run: run
    } do
      {:ok, failed_run} = Gust.Flows.update_run_status(run, :failed)

      GustWeb.DAGRunRestarterMock |> expect(:restart_run, fn ^failed_run -> nil end)

      {:ok, run_live, _html} =
        live(conn, ~p"/dags/#{dag.name}/runs?run_id=#{failed_run.id}")

      assert run_live |> element("#restart-run") |> render_click() =~
               "Run: #{failed_run.id} was restarted"
    end

    test "click restart task on failed task", %{
      conn: conn,
      dag: dag,
      run: run,
      task: task
    } do
      {:ok, failed_task} = Gust.Flows.update_task_status(task, :failed)

      GustWeb.DAGRunRestarterMock |> expect(:restart_task, fn _tasks, ^failed_task -> nil end)

      {:ok, run_live, _html} =
        live(conn, ~p"/dags/#{dag.name}/runs?run_id=#{run.id}&task_name=#{failed_task.name}")

      assert run_live |> element("#restart-task") |> render_click() =~
               "Task: #{failed_task.name} was restarted"
    end

    test "click restart task on succeeded task", %{
      conn: conn,
      dag: dag,
      run: run,
      task: task
    } do
      {:ok, succeeded_task} = Gust.Flows.update_task_status(task, :succeeded)

      GustWeb.DAGRunRestarterMock |> expect(:restart_task, fn _tasks, ^succeeded_task -> nil end)

      {:ok, run_live, _html} =
        live(conn, ~p"/dags/#{dag.name}/runs?run_id=#{run.id}&task_name=#{succeeded_task.name}")

      assert run_live |> element("#restart-task") |> render_click() =~
               "Task: #{succeeded_task.name} was restarted"
    end

    test "click restart task on running task", %{
      conn: conn,
      dag: dag,
      run: run,
      task: task
    } do
      {:ok, run_live, _html} =
        live(conn, ~p"/dags/#{dag.name}/runs?run_id=#{run.id}&task_name=#{task.name}")

      refute run_live |> has_element?("#restart-task")
    end

    test "no cancel button for created run", %{
      conn: conn,
      dag: dag,
      run: run
    } do
      {:ok, run_live, _html} =
        live(conn, ~p"/dags/#{dag.name}/runs?run_id=#{run.id}")

      refute run_live |> has_element?("#restart-run")
    end

    test "no cancel button for not running task", %{
      conn: conn,
      dag: dag,
      run: run,
      task: task
    } do
      {:ok, run_live, _html} =
        live(conn, ~p"/dags/#{dag.name}/runs?run_id=#{run.id}&task_name=#{task.name}")

      refute run_live |> has_element?("#cancel-task")
    end

    test "click on trigger", %{
      conn: conn,
      dag: dag
    } do
      {:ok, run_live, _html} = live(conn, ~p"/dags/#{dag.name}/runs")
      dag_id = dag.id

      new_run = run_fixture(%{dag_id: dag_id})

      GustWeb.DAGRunRestarterMock |> expect(:start_dag, fn ^dag_id -> new_run end)

      assert run_live |> element("#trigger-dag-run-#{dag.id}") |> render_click() =~
               "Run #{new_run.id} triggered"
    end
  end
end
