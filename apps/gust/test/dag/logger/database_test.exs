defmodule DAG.Logger.DatabaseTest do
  require Logger
  use Gust.DataCase
  import Gust.FlowsFixtures
  alias Gust.DAG.Logger.Database
  alias Gust.Flows
  alias Gust.PubSub
  import ExUnit.CaptureLog

  describe "set_task/1" do
    setup do
      attempt = 1..10 |> Enum.random()
      task_name = "hi"
      dag = dag_fixture()
      run = run_fixture(%{dag_id: dag.id})
      task = task_fixture(%{run_id: run.id, name: task_name, attempt: attempt})

      log_content = "boogie"
      %{task: task, log_content: log_content}
    end

    test "do not for non task log", %{task: task, log_content: log_content} do
      task_id = task.id

      {:ok, log} =
        with_log(fn ->
          Logger.warning(log_content)
          Process.sleep(20)
        end)

      refute log =~ ":gen_event handler Gust.DAG.Logger.Database installed in Logger terminating"

      assert Flows.get_task_with_logs!(task_id).logs == []
    end

    test "log for nil messages", %{task: task} do
      task_id = task.id
      task_attempt = task.attempt
      Database.set_task(task.id, task_attempt)
      PubSub.subscribe_task(task_id)

      {:ok, _log} =
        with_log(fn ->
          Logger.warning("")
          Process.sleep(20)
        end)

      [task_log] = Flows.get_task_with_logs!(task_id).logs
      assert task_log.content == "nil or empty was logged!"
      assert task_log.level == "error"
    end

    test "log for list messages", %{task: task} do
      task_id = task.id
      task_attempt = task.attempt
      Database.set_task(task.id, task_attempt)
      PubSub.subscribe_task(task_id)

      {:ok, _log} =
        with_log(fn ->
          Logger.warning(["hello", "world"])
          Process.sleep(20)
        end)

      [task_log] = Flows.get_task_with_logs!(task_id).logs
      assert task_log.content == "hello; world"
    end

    test "log for maps messages", %{task: task} do
      task_id = task.id
      task_attempt = task.attempt
      Database.set_task(task.id, task_attempt)
      PubSub.subscribe_task(task_id)
      msg = %{"hello" => "world"}

      {:ok, _log} =
        with_log(fn ->
          Logger.warning(msg)
          Process.sleep(20)
        end)

      [task_log] = Flows.get_task_with_logs!(task_id).logs
      assert task_log.content == "[{\"hello\", \"world\"}]"
    end

    test "creates a warning log for task", %{task: task, log_content: log_content} do
      task_id = task.id
      task_attempt = task.attempt
      Database.set_task(task.id, task_attempt)
      PubSub.subscribe_task(task_id)

      {:ok, _log} =
        with_log(fn ->
          Logger.warning(log_content)
          Process.sleep(20)
        end)

      Database.unset()

      assert [%Flows.Log{level: "warn", content: ^log_content, attempt: ^task_attempt}] =
               logs =
               Flows.get_task_with_logs!(task_id).logs

      log_id = List.first(logs).id
      assert_receive {:task, :log, %{task_id: ^task_id, log_id: ^log_id}}

      assert :ok = Logger.configure_backend(Database, foo: :bar)
    end
  end

  describe "unset" do
    test "remove logger metadata" do
      Logger.metadata(task_id: 123)
      Database.unset()

      assert Logger.metadata() == []
    end
  end
end
