defmodule GustPy.TaskWorker.AdapterTest do
  use ExUnit.Case, async: false
  import Mox
  import ExUnit.CaptureLog
  alias Gust.DAG.Definition
  alias Gust.Flows.Task
  alias GustPy.TaskWorker.Adapter
  alias GustPy.TaskWorker.Error

  setup :verify_on_exit!
  setup :set_mox_from_context

  setup do
    state = %{
      task: %Task{id: 100, run_id: 200, attempt: 1, name: "task_alpha"},
      dag_def: %Definition{name: "demo_dag", file_path: "/tmp/demo.py"},
      stage_pid: self()
    }

    %{state: state}
  end

  def setup_port(%{state: state}) do
    port = :task_port
    state = Map.merge(state, %{port: port})
    %{state: state}
  end

  def unset_logging(state) do
    GustPy.DAGLoggerMock |> expect(:unset, fn -> :ok end)
    state
  end

  describe "handle_cast/2 when :kill is given" do
    test "kills the OS python process and stops" do
      port =
        Port.open({:spawn_executable, System.find_executable("sleep")}, [
          :exit_status,
          args: ["30"]
        ])

      {:os_pid, os_python_pid} = Port.info(port, :os_pid)
      state = %{os_python_pid: os_python_pid}

      assert {:stop, :normal, ^state} = Adapter.handle_cast({:kill}, state)

      assert_receive {^port, {:exit_status, _status}}, 1_000

      assert {stderr, 1} =
               System.cmd("kill", ["-0", Integer.to_string(os_python_pid)],
                 stderr_to_stdout: true
               )

      assert stderr =~ Integer.to_string(os_python_pid)
    end
  end

  describe "handle_info/2 when :run is given" do
    test "start port and set on state", %{
      state: %{dag_def: dag_def, task: %Task{name: task_name, run_id: run_id}} = state
    } do
      port = :task_port

      GustPy.DAGLoggerMock |> expect(:set_task, fn _task_name, _attempt -> nil end)

      GustPy.ExecutorMock
      |> expect(:start_task_via_port, fn ^dag_def, ^task_name, %{run_id: ^run_id} ->
        port
      end)

      assert {:noreply, next_state} = Adapter.handle_info(:run, state)
      assert next_state.port == port
    end
  end

  describe "handle_info/2 when port is given" do
    setup [:setup_port]

    test "message is decoded and replied",
         %{
           state:
             %{
               port: port,
               dag_def: _dag_def,
               task: %Task{name: _task_name, run_id: _run_id}
             } = state
         } do
      msg = %{"type" => "call", "op" => "get_secret_by_name"}
      payload = %{ok: true, data: %{value: "secret"}}

      GustPy.TaskMessengerMock
      |> expect(:decode, fn "payload" -> {:ok, msg} end)
      |> expect(:handle_next, fn ^msg -> {:reply, payload} end)
      |> expect(:reply, fn ^port, ^payload -> :ok end)

      assert {:noreply, returned_state} = Adapter.handle_info({port, {:data, "payload"}}, state)
      assert returned_state == state
    end

    test " port data skips replies when messenger returns noreply", %{
      state:
        %{
          port: port,
          dag_def: _dag_def,
          task: %Task{name: _task_name, run_id: _run_id}
        } = state
    } do
      msg = %{"type" => "log", "msg" => "hello"}

      GustPy.TaskMessengerMock
      |> expect(:decode, fn "payload" -> {:ok, msg} end)
      |> expect(:handle_next, fn ^msg -> :noreply end)

      assert {:noreply, returned_state} = Adapter.handle_info({port, {:data, "payload"}}, state)
      assert returned_state == state
    end

    test "port data ignores decode errors", %{
      state:
        %{
          port: port,
          dag_def: _dag_def,
          task: %Task{name: _task_name, run_id: _run_id}
        } = state
    } do
      error_msg = "boom"

      GustPy.TaskMessengerMock
      |> expect(:decode, fn "payload" -> {:error, RuntimeError.exception(error_msg)} end)

      {:ok, log} =
        with_log(fn ->
          assert {:noreply, returned_state} =
                   Adapter.handle_info({port, {:data, "payload"}}, state)

          assert returned_state == state
          :ok
        end)

      assert log =~ "Failed to decode port message"
      assert log =~ error_msg
    end

    test "port data records done messages", %{
      state:
        %{
          port: port,
          dag_def: _dag_def,
          task: %Task{name: _task_name, run_id: _run_id}
        } = state
    } do
      msg = %{"type" => "result"}

      GustPy.TaskMessengerMock
      |> expect(:decode, fn "payload" -> {:ok, msg} end)
      |> expect(:handle_next, fn ^msg -> {:done, {:result, %{ok: true}}} end)

      assert {:noreply, returned_state} = Adapter.handle_info({port, {:data, "payload"}}, state)
      assert returned_state.done == {:result, %{ok: true}}
    end
  end

  describe "handle_info/2 when exit_status is called" do
    setup [:setup_port, :unset_logging]

    test "exit_status forwards done result on exit", %{
      state:
        %{
          port: port,
          dag_def: _dag_def,
          task: %Task{name: _task_name, run_id: _run_id}
        } = state
    } do
      answer = 42
      state = Map.put(state, :done, {:result, %{answer: answer}})

      assert {:stop, :normal, ^state} = Adapter.handle_info({port, {:exit_status, 0}}, state)

      assert_receive {:task_result, %{answer: ^answer}, 100, :ok}
    end

    test "handle_info exit_status forwards done error on exit", %{
      state:
        %{
          port: port,
          dag_def: _dag_def,
          task: %Task{name: _task_name, run_id: _run_id}
        } = state
    } do
      error = Error.new(:task_failed, "boom")
      state = Map.put(state, :done, {:error, error})

      assert {:stop, :normal, ^state} = Adapter.handle_info({port, {:exit_status, 0}}, state)

      assert_receive {:task_result, %Error{type: :task_failed, reason: "boom"}, 100, :error}
    end

    test "exit_status forwards port exits as task errors when no done message", %{
      state:
        %{
          port: port,
          dag_def: _dag_def,
          task: %Task{name: _task_name, run_id: _run_id}
        } = state
    } do
      assert {:stop, :normal, ^state} = Adapter.handle_info({port, {:exit_status, 2}}, state)

      assert_receive {:task_result, %Error{type: :port_exit, reason: "died with: 2"}, 100, :error}
    end
  end
end
