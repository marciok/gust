defmodule GustWeb.DagLive.Dashboard.HealthCheckLiveTest do
  use GustWeb.ConnCase

  import Phoenix.LiveViewTest
  import Gust.FlowsFixtures
  import Mox

  alias Gust.DAG.Definition
  alias Gust.DAG.TaskWorker
  alias GustWeb.HealthCheckComponent
  alias Phoenix.LiveView.AsyncResult

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    dag = dag_fixture(%{name: "health_dag"})
    run = run_fixture(%{dag_id: dag.id, status: :running})
    task = task_fixture(%{run_id: run.id, name: "work", status: :running})

    dag_file = Path.join(System.tmp_dir!(), "health_dag_#{System.unique_integer([:positive])}.ex")
    File.write!(dag_file, "# health dag")
    on_exit(fn -> File.rm_rf!(dag_file) end)

    dag_def = %Definition{
      name: dag.name,
      mod: MockDagMod,
      task_list: [task.name],
      stages: [[task.name]],
      tasks: %{task.name => %{upstream: MapSet.new(), downstream: MapSet.new()}},
      options: [],
      file_path: dag_file
    }

    stub(GustWeb.DAGLoaderMock, :get_definition, fn _dag_id -> {:ok, dag_def} end)

    %{dag: dag, run: run, task: task}
  end

  test "shows a running task with a live worker as healthy", %{conn: conn} = ctx do
    register(TaskWorker.registry_name(ctx.task))
    view = open_dashboard(conn, ctx)

    view |> element("#health-check") |> render_click()
    render_async(view)

    assert has_element?(view, "#health-modal")
    assert has_element?(view, "#health-verdict-#{ctx.task.id}[data-verdict='healthy']")
    assert has_element?(view, "#health-node-connected", "yes")

    for key <- [:status, :current_function, :message_queue_len, :reductions] do
      assert has_element?(view, "#health-info-#{key}-#{ctx.task.id}")
    end

    assert has_element?(view, "#health-info-memory-#{ctx.task.id}", "bytes")
  end

  test "flags a running task without a worker as a zombie", %{conn: conn} = ctx do
    view = open_dashboard(conn, ctx)

    view |> element("#health-check") |> render_click()
    render_async(view)

    assert has_element?(view, "#health-verdict-#{ctx.task.id}[data-verdict='zombie']")
  end

  test "shows unknown when the owner node is unreachable", %{conn: conn} = ctx do
    {:ok, _run} =
      ctx.run
      |> Ecto.Changeset.change(
        claimed_by: "missing-owner@invalid",
        claim_expires_at: DateTime.add(DateTime.utc_now(), 60, :second)
      )
      |> Gust.Repo.update()

    view = open_dashboard(conn, ctx)

    view |> element("#health-check") |> render_click()
    render_async(view)

    assert has_element?(view, "#health-error")
    assert has_element?(view, "#health-verdict-#{ctx.task.id}[data-verdict='unknown']")
    assert has_element?(view, "#health-node-connected", "no")
  end

  test "refresh re-runs the check and close hides the modal", %{conn: conn} = ctx do
    view = open_dashboard(conn, ctx)

    view |> element("#health-check") |> render_click()
    render_async(view)
    assert has_element?(view, "#health-verdict-#{ctx.task.id}[data-verdict='zombie']")

    register(TaskWorker.registry_name(ctx.task))
    view |> element("#health-refresh") |> render_click()
    render_async(view)
    assert has_element?(view, "#health-verdict-#{ctx.task.id}[data-verdict='healthy']")

    view |> element("#health-close") |> render_click()
    refute has_element?(view, "#health-modal")
  end

  test "polls while the modal is open", %{conn: conn} = ctx do
    replace_web_env(:health_check_interval, 20)
    view = open_dashboard(conn, ctx)

    view |> element("#health-check") |> render_click()
    render_async(view)
    assert has_element?(view, "#health-verdict-#{ctx.task.id}[data-verdict='zombie']")

    register(TaskWorker.registry_name(ctx.task))

    assert eventually(fn ->
             render_async(view)
             has_element?(view, "#health-verdict-#{ctx.task.id}[data-verdict='healthy']")
           end)
  end

  test "stops polling once the modal is closed", %{conn: conn} = ctx do
    replace_web_env(:health_check_interval, 10)
    view = open_dashboard(conn, ctx)

    view |> element("#health-check") |> render_click()
    render_async(view)
    view |> element("#health-close") |> render_click()

    Process.sleep(50)
    render_async(view)
    refute has_element?(view, "#health-modal")
  end

  test "shows a worker that is registered but no longer alive as dead" do
    report = %{
      checked_at: DateTime.utc_now(),
      error: nil,
      run: %{
        id: 1,
        status: :running,
        claimed_by: nil,
        claim_expires_at: nil,
        owner_node: to_string(node()),
        node_connected: true,
        dag_worker: nil
      },
      tasks: [
        %{
          id: 7,
          name: "work",
          map_index: nil,
          status: :running,
          registry_key: "task_7",
          verdict: :zombie,
          process: %{pid: "#PID<0.1.0>", alive: false, info: nil, os_process: nil}
        }
      ]
    }

    html =
      render_component(HealthCheckComponent,
        id: "health",
        selected_item: nil,
        health_check: AsyncResult.ok(report)
      )

    worker = html |> LazyHTML.from_fragment() |> LazyHTML.query("#health-task-worker-7")

    assert LazyHTML.text(worker) =~ "#PID<0.1.0> (dead)"
  end

  test "shows the external OS process of a task worker", %{conn: conn} = ctx do
    os_pid = String.to_integer(System.pid())
    register(TaskWorker.registry_name(ctx.task), %{os_pid: os_pid})
    view = open_dashboard(conn, ctx)

    view |> element("#health-check") |> render_click()
    render_async(view)

    assert has_element?(view, "#health-os-process-#{ctx.task.id}", "#{os_pid} (alive)")
  end

  @tag :capture_log
  test "shows a failure when the check itself crashes", %{conn: conn} = ctx do
    view = open_dashboard(conn, ctx)
    {:ok, _run} = Gust.Flows.delete_run(ctx.run)

    view |> element("#health-check") |> render_click()
    render_async(view)

    assert has_element?(view, "#health-failed")
    refute has_element?(view, "#health-report")
  end

  test "refresh does nothing while the modal is closed", %{conn: conn} = ctx do
    view = open_dashboard(conn, ctx)

    view
    |> with_target("#health-check-component")
    |> render_click("refresh", %{})

    refute has_element?(view, "#health-modal")
  end

  test "drops a check result that arrives after the modal closed" do
    socket = component_socket(health_check: nil, tick_token: nil)

    assert {:noreply, ^socket} =
             HealthCheckComponent.handle_async(:health_check, {:ok, %{}}, socket)
  end

  describe "poll ticks" do
    test "are ignored while the modal is closed" do
      socket = component_socket(health_check: nil, tick_token: nil)

      assert {:ok, ^socket} =
               HealthCheckComponent.update(%{id: "health", tick: make_ref()}, socket)
    end

    test "are ignored when they belong to an older check" do
      socket =
        component_socket(health_check: AsyncResult.ok(%{}), tick_token: make_ref())

      assert {:ok, ^socket} =
               HealthCheckComponent.update(%{id: "health", tick: make_ref()}, socket)
    end
  end

  describe "mapped tasks" do
    setup %{run: run, task: task} do
      {:ok, first} = Gust.Flows.update_task_mapping(task, 0, %{})
      second = task_fixture(%{run_id: run.id, name: task.name, status: :running, map_index: 1})
      %{first: first, second: second}
    end

    test "each mapped task row has its own health check", %{conn: conn} = ctx do
      view = open_dashboard(conn, ctx)

      assert has_element?(view, "#mapped-task-runs")
      refute has_element?(view, "#health-check")
      assert has_element?(view, "#health-mapped-task-#{ctx.first.id}")

      view |> element("#health-mapped-task-#{ctx.second.id}") |> render_click()
      render_async(view)

      assert has_element?(view, "#health-task-#{ctx.second.id}")
      refute has_element?(view, "#health-task-#{ctx.first.id}")
    end

    test "ignores a mapped task id outside the selected group", %{conn: conn} = ctx do
      view = open_dashboard(conn, ctx)

      view
      |> with_target("#health-check-component")
      |> render_click("open", %{"task-id" => "-1"})

      refute has_element?(view, "#health-modal")
    end

    test "checks only the selected mapped task", %{conn: conn} = ctx do
      {:ok, view, _html} =
        live(
          conn,
          ~g"/dags/#{ctx.dag.name}/dashboard?run_id=#{ctx.run.id}&task_name=#{ctx.task.name}&task_index=1"
        )

      refute has_element?(view, "#health-check[disabled]")
      view |> element("#health-check") |> render_click()
      render_async(view)

      assert has_element?(view, "#health-task-#{ctx.second.id}")
      refute has_element?(view, "#health-task-#{ctx.first.id}")
    end
  end

  test "checks a selected run and its running tasks", %{conn: conn} = ctx do
    register("dag_run_#{ctx.run.id}")
    done = task_fixture(%{run_id: ctx.run.id, name: "done", status: :succeeded})

    {:ok, view, _html} = live(conn, ~g"/dags/#{ctx.dag.name}/dashboard?run_id=#{ctx.run.id}")

    view |> element("#health-check") |> render_click()
    render_async(view)

    assert has_element?(view, "#health-dag-worker", "alive")
    assert has_element?(view, "#health-verdict-#{ctx.task.id}[data-verdict='zombie']")
    refute has_element?(view, "#health-task-#{done.id}")
  end

  test "a run without running tasks says so", %{conn: conn} = ctx do
    {:ok, _task} = Gust.Flows.update_task_status(ctx.task, :succeeded)
    {:ok, view, _html} = live(conn, ~g"/dags/#{ctx.dag.name}/dashboard?run_id=#{ctx.run.id}")

    view |> element("#health-check") |> render_click()
    render_async(view)

    assert has_element?(view, "#health-no-tasks")
  end

  test "checks tasks that are not running", %{conn: conn} = ctx do
    {:ok, _task} = Gust.Flows.update_task_status(ctx.task, :succeeded)
    view = open_dashboard(conn, ctx)

    refute has_element?(view, "#health-check[disabled]")
    view |> element("#health-check") |> render_click()
    render_async(view)

    assert has_element?(view, "#health-verdict-#{ctx.task.id}[data-verdict='not_running']")
  end

  defp open_dashboard(conn, %{dag: dag, run: run, task: task}) do
    {:ok, view, _html} =
      live(conn, ~g"/dags/#{dag.name}/dashboard?run_id=#{run.id}&task_name=#{task.name}")

    view
  end

  defp component_socket(assigns) do
    %Phoenix.LiveView.Socket{
      assigns: Map.merge(%{__changed__: %{}, id: "health", check_target: nil}, Map.new(assigns))
    }
  end

  defp replace_web_env(key, value) do
    previous = Application.fetch_env(:gust_web, key)
    Application.put_env(:gust_web, key, value)

    on_exit(fn ->
      case previous do
        {:ok, previous_value} -> Application.put_env(:gust_web, key, previous_value)
        :error -> Application.delete_env(:gust_web, key)
      end
    end)
  end

  defp eventually(check, attempts \\ 50) do
    cond do
      check.() -> true
      attempts == 0 -> false
      true -> Process.sleep(10) && eventually(check, attempts - 1)
    end
  end

  defp register(key, value \\ nil) do
    parent = self()

    pid =
      spawn(fn ->
        {:ok, _owner} = Registry.register(Gust.Registry, key, value)
        send(parent, {:registered, self()})

        receive do
          :stop -> :ok
        end
      end)

    assert_receive {:registered, ^pid}
    on_exit(fn -> Process.exit(pid, :kill) end)
    pid
  end
end
