defmodule GustPy.TaskMessenger.JSONTest do
  use Gust.DataCase
  import ExUnit.CaptureLog
  import Gust.FlowsFixtures

  alias GustPy.TaskMessenger.JSON
  alias GustPy.TaskWorker.Error

  describe "decode/1" do
    test "decodes log message" do
      payload = %{"type" => "log", "msg" => "hello"}
      assert {:ok, %JSON{type: :log, msg: "hello"}} = JSON.decode(Jason.encode!(payload))
    end

    test "decodes call message for get_secret_by_name" do
      payload = %{"type" => "call", "op" => "get_secret_by_name", "name" => "SOME_NAME"}

      assert {:ok, %JSON{type: :call, op: :get_secret_by_name, name: "SOME_NAME"}} =
               JSON.decode(Jason.encode!(payload))
    end

    test "decodes call message for get_task_by_name_run when task exists" do
      payload = %{
        "type" => "call",
        "op" => "get_task_by_name_run",
        "name" => "task_alpha",
        "run_id" => 42
      }

      assert {:ok,
              %JSON{
                type: :call,
                op: :get_task_by_name_run,
                name: "task_alpha",
                run_id: 42
              }} = JSON.decode(Jason.encode!(payload))
    end

    test "decodes result message" do
      payload = %{"type" => "result", "ok" => true, "data" => %{"value" => 123}}

      assert {:ok, %JSON{type: :result, ok: true, data: %{"value" => 123}}} =
               JSON.decode(Jason.encode!(payload))
    end

    test "decodes error message" do
      payload = %{"type" => "error", "ok" => false, "trace" => "boom"}

      assert {:ok, %JSON{type: :error, ok: false, trace: "boom"}} =
               JSON.decode(Jason.encode!(payload))
    end

    test "decodes unknown message types" do
      payload = %{"type" => "weird", "data" => %{"ok" => true}}
      assert {:ok, %JSON{type: :unknown, data: ^payload}} = JSON.decode(Jason.encode!(payload))
    end

    test "returns error on invalid json" do
      assert {:error, %Jason.DecodeError{}} = JSON.decode("not-json")
    end
  end

  describe "handle_next/1" do
    test "logs :log messages and returns :noreply" do
      capture_log([level: :info], fn ->
        assert :noreply = JSON.handle_next(%JSON{type: :log, msg: "hello"})
      end)
    end

    test "returns reply with secret when found" do
      secret = secret_fixture(%{name: unique_secret_name()})

      assert {:reply, %{ok: true, data: data}} =
               JSON.handle_next(%JSON{type: :call, op: :get_secret_by_name, name: secret.name})

      assert data == %{
               id: secret.id,
               name: secret.name,
               value_type: secret.value_type,
               value: secret.value
             }
    end

    test "returns not found when secret is missing" do
      assert {:reply, %{ok: false, error: "secret_not_found"}} =
               JSON.handle_next(%JSON{type: :call, op: :get_secret_by_name, name: "MISSING"})
    end

    test "returns reply with task when found" do
      dag = dag_fixture(%{name: unique_dag_name()})
      run = run_fixture(%{dag_id: dag.id})
      task = task_fixture(%{run_id: run.id, name: "task_alpha", result: %{"value" => 55}})

      assert {:reply, %{ok: true, data: data}} =
               JSON.handle_next(%JSON{
                 type: :call,
                 op: :get_task_by_name_run,
                 name: "task_alpha",
                 run_id: run.id
               })

      assert data == %{id: task.id, result: %{"value" => 55}}
    end

    test "rasise when task when found" do
      dag = dag_fixture(%{name: unique_dag_name()})
      run = run_fixture(%{dag_id: dag.id})
      task_fixture(%{run_id: run.id, name: "task_alpha", result: %{"value" => 55}})

      not_found_task = "task_alpha_sum_41"

      assert_raise RuntimeError,
                   ~r"Task #{not_found_task} not found in run_id: #{run.id}",
                   fn ->
                     JSON.handle_next(%JSON{
                       type: :call,
                       op: :get_task_by_name_run,
                       name: not_found_task,
                       run_id: run.id
                     })
                   end
    end

    test "returns done with result value from map" do
      msg = %JSON{type: :result, ok: true, data: %{"value" => "ok"}}
      assert {:done, {:result, "ok"}} = JSON.handle_next(msg)
    end

    test "returns done with result value for non-map" do
      msg = %JSON{type: :result, ok: true, data: 123}
      assert {:done, {:result, 123}} = JSON.handle_next(msg)
    end

    test "returns done with error" do
      msg = %JSON{type: :error, ok: false, trace: "boom"}

      assert {:done, {:error, %Error{type: :task_failed, reason: "boom"}}} =
               JSON.handle_next(msg)
    end

    test "logs unknown messages and returns :noreply" do
      capture_log([level: :warning], fn ->
        assert :noreply = JSON.handle_next(%JSON{type: :unknown, data: %{}})
      end)
    end
  end

  describe "reply/2" do
    test "encodes payload and sends it to the port" do
      port = Port.open({:spawn, "cat"}, [:binary, :exit_status])

      on_exit(fn ->
        if Port.info(port) do
          Port.close(port)
        end
      end)

      payload = %{ok: true, data: %{value: "secret"}}
      expected = payload |> Map.put_new(:type, "reply") |> Jason.encode!()

      assert :ok = JSON.reply(port, payload)
      assert_receive {^port, {:data, ^expected}}
    end
  end

  defp unique_secret_name do
    "SECRET_#{System.unique_integer([:positive])}"
  end

  defp unique_dag_name do
    "dag_#{System.unique_integer([:positive])}"
  end
end
