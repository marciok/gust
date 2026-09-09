defmodule GustPy.TaskWorker.AdapterTest do
  use ExUnit.Case, async: false
  import Mox
  import ExUnit.CaptureLog
  alias Gust.DAG.Definition
  alias Gust.Flows.Task
  alias GustPy.TaskMessenger.FrameCodec
  alias GustPy.TaskWorker.Adapter
  alias GustPy.TaskWorker.Error

  setup :verify_on_exit!
  setup :set_mox_from_context

  setup do
    state = %{
      task: %Task{id: 100, run_id: 200, attempt: 1, name: "task_alpha"},
      dag_def: %Definition{name: "demo_dag", file_path: "/tmp/demo.py"},
      owner_pid: self()
    }

    %{state: state}
  end

  def setup_os_pid(%{state: state}) do
    os_pid = 99_999
    state = Map.merge(state, %{os_pid: os_pid, buffer: <<>>})
    %{state: state}
  end

  def unset_logging(state) do
    GustPy.DAGLoggerMock |> expect(:unset, fn -> :ok end)
    state
  end

  describe "handle_cast/2 when :kill is given" do
    test "kills the OS process group, including grandchildren" do
      {:ok, _pid, os_pid} =
        :exec.run(["/bin/sh", "-c", "sleep 30 & echo $!; wait"], [
          :monitor,
          {:stdout, self()},
          {:group, 0},
          :kill_group
        ])

      grandchild_pid =
        receive do
          {:stdout, ^os_pid, data} -> data |> String.trim() |> String.to_integer()
        after
          1_000 -> flunk("did not receive grandchild pid")
        end

      state = %{os_pid: os_pid}

      assert {:stop, :normal, ^state} = Adapter.handle_cast({:kill}, state)

      assert_receive {:DOWN, ^os_pid, :process, _pid, _reason}, 1_000

      assert {_, 1} =
               System.cmd("kill", ["-0", Integer.to_string(grandchild_pid)],
                 stderr_to_stdout: true
               )
    end
  end

  describe "handle_info/2 when :run is given" do
    test "starts the task and sets the os pid on state", %{
      state: %{dag_def: dag_def, task: %Task{name: task_name, run_id: run_id}} = state
    } do
      os_pid = 4242

      GustPy.DAGLoggerMock |> expect(:set_task, fn _task_name, _attempt -> nil end)

      GustPy.ExecutorMock
      |> expect(:start_task, fn ^dag_def, ^task_name, %{run_id: ^run_id} ->
        os_pid
      end)

      assert {:noreply, next_state} = Adapter.handle_info(:run, state)
      assert next_state.os_pid == os_pid
      assert next_state.buffer == <<>>
    end

    test "passes persisted params for mapped tasks", %{state: state} do
      params = %{"model" => "mapped"}
      task = %{state.task | map_index: 1, params: params}
      state = %{state | task: task}
      os_pid = 4242

      GustPy.DAGLoggerMock |> expect(:set_task, fn _task_name, _attempt -> nil end)

      GustPy.ExecutorMock
      |> expect(:start_task, fn dag_def,
                                task_name,
                                %{
                                  run_id: run_id,
                                  params: ^params
                                } ->
        assert dag_def == state.dag_def
        assert task_name == task.name
        assert run_id == task.run_id
        os_pid
      end)

      assert {:noreply, next_state} = Adapter.handle_info(:run, state)
      assert next_state.os_pid == os_pid
    end
  end

  describe "handle_info/2 when stdout data is given" do
    setup [:setup_os_pid]

    test "message is decoded and replied", %{state: %{os_pid: os_pid} = state} do
      msg = %{"type" => "call", "op" => "get_secret_by_name"}
      payload = %{ok: true, data: %{value: "secret"}}
      frame = FrameCodec.encode("payload")

      GustPy.TaskMessengerMock
      |> expect(:decode, fn "payload" -> {:ok, msg} end)
      |> expect(:handle_next, fn ^msg -> {:reply, payload} end)
      |> expect(:reply, fn ^os_pid, ^payload -> :ok end)

      assert {:noreply, returned_state} = Adapter.handle_info({:stdout, os_pid, frame}, state)
      assert returned_state == state
    end

    test "skips replies when messenger returns noreply", %{state: %{os_pid: os_pid} = state} do
      msg = %{"type" => "log", "msg" => "hello"}
      frame = FrameCodec.encode("payload")

      GustPy.TaskMessengerMock
      |> expect(:decode, fn "payload" -> {:ok, msg} end)
      |> expect(:handle_next, fn ^msg -> :noreply end)

      assert {:noreply, returned_state} = Adapter.handle_info({:stdout, os_pid, frame}, state)
      assert returned_state == state
    end

    test "ignores decode errors", %{state: %{os_pid: os_pid} = state} do
      error_msg = "boom"
      frame = FrameCodec.encode("payload")

      GustPy.TaskMessengerMock
      |> expect(:decode, fn "payload" -> {:error, RuntimeError.exception(error_msg)} end)

      {:ok, log} =
        with_log(fn ->
          assert {:noreply, returned_state} =
                   Adapter.handle_info({:stdout, os_pid, frame}, state)

          assert returned_state == state
          :ok
        end)

      assert log =~ "Failed to decode task message"
      assert log =~ error_msg
    end

    test "records done messages", %{state: %{os_pid: os_pid} = state} do
      msg = %{"type" => "result"}
      frame = FrameCodec.encode("payload")

      GustPy.TaskMessengerMock
      |> expect(:decode, fn "payload" -> {:ok, msg} end)
      |> expect(:handle_next, fn ^msg -> {:done, {:result, %{ok: true}}} end)

      assert {:noreply, returned_state} = Adapter.handle_info({:stdout, os_pid, frame}, state)
      assert returned_state.done == {:result, %{ok: true}}
    end

    test "buffers a frame split across multiple chunks", %{state: %{os_pid: os_pid} = state} do
      msg = %{"type" => "log", "msg" => "hello"}
      frame = FrameCodec.encode("payload")
      <<head::binary-size(3), tail::binary>> = frame

      GustPy.TaskMessengerMock
      |> expect(:decode, fn "payload" -> {:ok, msg} end)
      |> expect(:handle_next, fn ^msg -> :noreply end)

      assert {:noreply, partial_state} = Adapter.handle_info({:stdout, os_pid, head}, state)
      assert partial_state.buffer == head

      assert {:noreply, returned_state} =
               Adapter.handle_info({:stdout, os_pid, tail}, partial_state)

      assert returned_state.buffer == <<>>
    end

    test "logs stderr data without changing state", %{state: %{os_pid: os_pid} = state} do
      {result, log} =
        with_log(fn -> Adapter.handle_info({:stderr, os_pid, "boom"}, state) end)

      assert {:noreply, returned_state} = result
      assert returned_state == state
      assert log =~ "boom"
    end
  end

  describe "handle_info/2 when the OS process exits" do
    setup [:setup_os_pid, :unset_logging]

    test "forwards done result on normal exit", %{state: %{os_pid: os_pid} = state} do
      answer = 42
      state = Map.put(state, :done, {:result, %{answer: answer}})

      assert {:stop, :normal, ^state} =
               Adapter.handle_info({:DOWN, os_pid, :process, self(), :normal}, state)

      assert_receive {:task_result, %{answer: ^answer}, 100, :ok}
    end

    test "forwards done error on normal exit", %{state: %{os_pid: os_pid} = state} do
      error = Error.new(:task_failed, "boom")
      state = Map.put(state, :done, {:error, error})

      assert {:stop, :normal, ^state} =
               Adapter.handle_info({:DOWN, os_pid, :process, self(), :normal}, state)

      assert_receive {:task_result, %Error{type: :task_failed, reason: "boom"}, 100, :error}
    end

    test "forwards non-normal exits as task errors when no done message", %{
      state: %{os_pid: os_pid} = state
    } do
      assert {:stop, :normal, ^state} =
               Adapter.handle_info(
                 {:DOWN, os_pid, :process, self(), {:exit_status, 2}},
                 state
               )

      assert_receive {:task_result,
                      %Error{type: :process_exit, reason: "died with: {:exit_status, 2}"}, 100,
                      :error}
    end
  end
end
