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
                {%Flows.Task{id: head_task_id, name: "insert_models", map_index: 0},
                 ^first_params}},
               {:ok, {%Flows.Task{name: "insert_models", map_index: 1}, ^second_params}},
               {:ok, {%Flows.Task{name: "insert_models", map_index: 2}, ^third_params}}
             ] =
               MapOver.expand_over(
                 [first_params, second_params, third_params],
                 task,
                 run.id,
                 create_fn
               )

      assert head_task_id == task.id
      assert Flows.get_task!(task.id).map_index == 0
      assert_receive {:create_task, "insert_models", 1}
      assert_receive {:create_task, "insert_models", 2}
      refute_receive {:create_task, "insert_models", 0}
    end
  end

  describe "get_params/2" do
    test "returns task items from a single upstream task result", %{run: run} do
      items = [%{"model" => "a"}, %{"model" => "b"}]

      task_fixture(%{
        run_id: run.id,
        name: "say_by",
        status: :succeeded,
        result: %{"gust_task_items" => items}
      })

      assert {:expand_task, ^items} = MapOver.get_params("say_by", run.id)
    end

    test "returns an error when the upstream task does not exist", %{run: run} do
      message = "Task: missing_task not found on run: #{run.id}"

      assert {:expand_task_error, %RuntimeError{message: ^message}} =
               MapOver.get_params("missing_task", run.id)
    end

    test "returns an error when the upstream task result is empty", %{run: run} do
      task_fixture(%{run_id: run.id, name: "say_by", result: %{}})

      assert {:expand_task_error, %RuntimeError{message: "Task: say_by result is empty"}} =
               MapOver.get_params("say_by", run.id)
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

      assert {:expand_task, [%{"a" => 1}, %{"b" => 2}]} = MapOver.get_params("say_by", run.id)
    end
  end
end
