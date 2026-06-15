defmodule Gust.DAG.TaskExpander.MapOverTest do
  use Gust.DataCase, async: true

  import Gust.FlowsFixtures

  alias Gust.DAG.TaskExpander.MapOver
  alias Gust.Flows

  setup do
    dag = dag_fixture()
    run = run_fixture(%{dag_id: dag.id})

    %{run: run}
  end

  describe "expand_over/4" do
    test "returns no task instances for an empty parameter list", %{run: run} do
      task = task_fixture(%{run_id: run.id, name: "insert_models"})

      assert MapOver.expand_over([], task, run.id, fn _, _ ->
               flunk("create function should not be called")
             end) == []

      assert Flows.get_task!(task.id).map_index == nil
    end

    test "updates the original task map index and creates mapped clones for remaining params", %{
      run: run
    } do
      task = task_fixture(%{run_id: run.id, name: "insert_models"})
      first_params = %{"model" => "a"}
      second_params = %{"model" => "b"}
      third_params = %{"model" => "c"}
      test_pid = self()

      create_fn = fn name, map_index ->
        send(test_pid, {:create_task, name, map_index})
        task_fixture(%{run_id: run.id, name: name, map_index: map_index})
      end

      assert [
               {:ok,
                {%Flows.Task{
                   id: head_task_id,
                   name: "insert_models",
                   map_index: 0,
                   params: ^first_params
                 }, ^first_params}},
               {:ok,
                {%Flows.Task{name: "insert_models", map_index: 1, params: ^second_params},
                 ^second_params}},
               {:ok,
                {%Flows.Task{name: "insert_models", map_index: 2, params: ^third_params},
                 ^third_params}}
             ] =
               MapOver.expand_over(
                 [first_params, second_params, third_params],
                 task,
                 run.id,
                 create_fn
               )

      assert head_task_id == task.id
      assert %Flows.Task{map_index: 0, params: ^first_params} = Flows.get_task!(task.id)
      assert_receive {:create_task, "insert_models", 1}
      assert_receive {:create_task, "insert_models", 2}
      refute_receive {:create_task, "insert_models", 0}
    end

    test "wraps scalar mapped params in an item map", %{run: run} do
      task = task_fixture(%{run_id: run.id, name: "insert_models"})
      first_params = %{"item" => "first"}
      second_params = %{"item" => "second"}

      assert [
               {:ok, {%Flows.Task{id: task_id, params: ^first_params}, ^first_params}},
               {:ok, {%Flows.Task{id: second_id, params: ^second_params}, ^second_params}}
             ] =
               MapOver.expand_over(["first", "second"], task, run.id, fn name, map_index ->
                 task_fixture(%{run_id: run.id, name: name, map_index: map_index})
               end)

      assert %Flows.Task{id: ^task_id, params: ^first_params} = Flows.get_task!(task_id)
      assert %Flows.Task{id: ^second_id, params: ^second_params} = Flows.get_task!(second_id)
    end
  end

  describe "collapse_each/1" do
    test "keeps the head task, clears its map index, and deletes the remaining tasks", %{run: run} do
      head =
        task_fixture(%{
          run_id: run.id,
          name: "insert_models",
          map_index: 0,
          params: %{"model" => "a"}
        })

      second = task_fixture(%{run_id: run.id, name: "insert_models", map_index: 1})
      third = task_fixture(%{run_id: run.id, name: "insert_models", map_index: 2})

      assert %Flows.Task{id: head_id, map_index: nil, params: %{}} =
               MapOver.collapse_each([head, second, third])

      assert head_id == head.id
      assert %Flows.Task{map_index: nil, params: %{}} = Flows.get_task!(head.id)
      assert_raise Ecto.NoResultsError, fn -> Flows.get_task!(second.id) end
      assert_raise Ecto.NoResultsError, fn -> Flows.get_task!(third.id) end
    end
  end

  describe "get_params/3" do
    test "returns task items from a single upstream task result", %{run: run} do
      items = [%{"model" => "a"}, %{"model" => "b"}]

      task_fixture(%{
        run_id: run.id,
        name: "say_by",
        status: :succeeded,
        result: %{"gust_task_items" => items}
      })

      assert {:expand_task, ^items} = MapOver.get_params("say_by", run.id, nil)
    end

    test "wraps scalar upstream items in item maps", %{run: run} do
      task_fixture(%{
        run_id: run.id,
        name: "say_by",
        status: :succeeded,
        result: %{"gust_task_items" => ["MARCIO"]}
      })

      assert {:expand_task, [%{"item" => "MARCIO"}]} =
               MapOver.get_params("say_by", run.id, nil)

      assert {:already_expanded, %{"item" => "MARCIO"}} =
               MapOver.get_params("say_by", run.id, 0)
    end

    test "returns params for a selected index from a single upstream task result", %{run: run} do
      items = [%{"model" => "a"}, %{"model" => "b"}]

      task_fixture(%{
        run_id: run.id,
        name: "say_by",
        status: :succeeded,
        result: %{"gust_task_items" => items}
      })

      assert {:already_expanded, %{"model" => "b"}} =
               MapOver.get_params("say_by", run.id, 1)
    end

    test "returns an error when the upstream task does not exist", %{run: run} do
      message = "Task: missing_task not found on run: #{run.id}"

      assert {:expand_task_error, %RuntimeError{message: ^message}} =
               MapOver.get_params("missing_task", run.id, nil)
    end

    test "returns an error when the upstream task result is empty", %{run: run} do
      task_fixture(%{run_id: run.id, name: "say_by", result: %{}})

      assert {:expand_task_error, %RuntimeError{message: "Task: say_by result is empty"}} =
               MapOver.get_params("say_by", run.id, nil)
    end

    test "returns an error when a selected index is out of range", %{run: run} do
      task_fixture(%{
        run_id: run.id,
        name: "say_by",
        result: %{"gust_task_items" => [%{"model" => "a"}]}
      })

      assert {:expand_task_error,
              %RuntimeError{message: "Task: say_by has no mapped result at index: 1"}} =
               MapOver.get_params("say_by", run.id, 1)
    end

    test "returns results from multiple upstream task instances", %{run: run} do
      task_fixture(%{
        run_id: run.id,
        name: "say_by",
        map_index: 0,
        result: %{"a" => 1}
      })

      task_fixture(%{
        run_id: run.id,
        name: "say_by",
        map_index: 1,
        result: %{"b" => 2}
      })

      assert {:expand_task, [%{"a" => 1}, %{"b" => 2}]} =
               MapOver.get_params("say_by", run.id, nil)
    end

    test "returns params for a selected index from multiple upstream task instances", %{run: run} do
      task_fixture(%{
        run_id: run.id,
        name: "say_by",
        map_index: 0,
        result: %{"a" => 1}
      })

      task_fixture(%{
        run_id: run.id,
        name: "say_by",
        map_index: 1,
        result: %{"b" => 2}
      })

      assert {:already_expanded, %{"b" => 2}} =
               MapOver.get_params("say_by", run.id, 1)
    end
  end
end
