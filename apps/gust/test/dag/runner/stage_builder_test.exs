defmodule Gust.DAG.Runner.StageBuilderTest do
  use Gust.DataCase, async: true

  import Gust.FlowsFixtures
  import Mox

  alias Gust.DAG.Definition
  alias Gust.DAG.Runner.StageBuilder
  alias Gust.DAG.TaskExpander.MapOver
  alias Gust.Flows

  setup :set_mox_from_context

  setup do
    stub_with(Gust.DAGStageCoordinatorMock, Gust.DAG.StageCoordinator.RetryingTask)
    stub_with(Gust.DAGTaskExpanderMock, Gust.DAG.TaskExpander.MapOver)

    dag = dag_fixture()
    run = run_fixture(%{dag_id: dag.id})

    %{run: run}
  end

  test "builds ordinary stage tasks and exposes their IDs", %{run: run} do
    dag_def =
      definition(%{
        "first" => task_options(),
        "second" => task_options()
      })

    assert [
             {:ok, %Flows.Task{id: first_id, name: "first"}},
             {:ok, %Flows.Task{id: second_id, name: "second"}}
           ] = stage = StageBuilder.build(["first", "second"], run.id, dag_def)

    assert StageBuilder.task_ids(stage) == [first_id, second_id]
  end

  test "expands a mapped task and persists each instance's params", %{run: run} do
    first_params = %{"model" => "a"}
    second_params = %{"model" => "b"}

    task_fixture(%{
      run_id: run.id,
      name: "source",
      status: :succeeded,
      result: %{"gust_task_items" => [first_params, second_params]}
    })

    dag_def =
      definition(%{
        "mapped" => task_options(upstream: ["source"], map_over: :source)
      })

    assert [
             {:ok,
              %Flows.Task{id: first_id, name: "mapped", map_index: 0, params: ^first_params}},
             {:ok,
              %Flows.Task{id: second_id, name: "mapped", map_index: 1, params: ^second_params}}
           ] = StageBuilder.build(["mapped"], run.id, dag_def)

    assert %Flows.Task{params: ^first_params} = Flows.get_task!(first_id)
    assert %Flows.Task{params: ^second_params} = Flows.get_task!(second_id)
  end

  test "marks a mapped task skipped when there is nothing to expand", %{run: run} do
    task_fixture(%{
      run_id: run.id,
      name: "source",
      status: :succeeded,
      result: %{"gust_task_items" => []}
    })

    dag_def =
      definition(%{
        "mapped" => task_options(upstream: ["source"], map_over: :source)
      })

    assert [{:skipped, %Flows.Task{name: "mapped", map_index: nil}}] =
             StageBuilder.build(["mapped"], run.id, dag_def)
  end

  test "returns a non-recoverable entry when mapped params cannot be loaded", %{run: run} do
    dag_def =
      definition(%{
        "mapped" => task_options(upstream: ["missing"], map_over: :missing)
      })

    assert [
             {{:non_recoverable_error,
               %RuntimeError{message: "Task: missing not found on run: " <> run_id}},
              %Flows.Task{name: "mapped"}}
           ] = StageBuilder.build(["mapped"], run.id, dag_def)

    assert run_id == to_string(run.id)
  end

  test "reconciles existing running mapped instances instead of duplicating them", %{run: run} do
    first_params = %{"model" => "a"}
    second_params = %{"model" => "b"}

    task_fixture(%{
      run_id: run.id,
      name: "source",
      status: :succeeded,
      result: %{"gust_task_items" => [first_params, second_params]}
    })

    first =
      task_fixture(%{
        run_id: run.id,
        name: "mapped",
        status: :running,
        map_index: 0,
        params: %{"stale" => true}
      })

    second =
      task_fixture(%{
        run_id: run.id,
        name: "mapped",
        status: :running,
        map_index: 1,
        params: %{"stale" => true}
      })

    dag_def =
      definition(%{
        "mapped" => task_options(upstream: ["source"], map_over: :source)
      })

    assert [
             {:ok,
              %Flows.Task{
                id: first_id,
                status: :created,
                map_index: 0,
                params: ^first_params
              }},
             {:ok,
              %Flows.Task{
                id: second_id,
                status: :created,
                map_index: 1,
                params: ^second_params
              }}
           ] = StageBuilder.build(["mapped"], run.id, dag_def)

    assert first_id == first.id
    assert second_id == second.id
    assert length(Flows.get_tasks_by_name("mapped", run.id)) == 2
  end

  test "resets a concurrently created running mapped instance during expansion", %{run: run} do
    params = [%{"model" => "a"}, %{"model" => "b"}]

    task_fixture(%{
      run_id: run.id,
      name: "source",
      status: :succeeded,
      result: %{"gust_task_items" => params}
    })

    dag_def =
      definition(%{
        "mapped" => task_options(upstream: ["source"], map_over: :source)
      })

    Gust.DAGTaskExpanderMock
    |> expect(:expand_over, fn ^params, task, run_id, create_fn ->
      task_fixture(%{
        run_id: run_id,
        name: task.name,
        status: :running,
        map_index: 1,
        params: %{"stale" => true}
      })

      MapOver.expand_over(params, task, run_id, create_fn)
    end)

    assert [
             {:ok, %Flows.Task{map_index: 0, params: %{"model" => "a"}}},
             {:ok,
              %Flows.Task{
                id: second_id,
                status: :created,
                map_index: 1,
                params: %{"model" => "b"}
              }}
           ] = StageBuilder.build(["mapped"], run.id, dag_def)

    assert %Flows.Task{id: ^second_id, status: :created} =
             Flows.get_task_by_name("mapped", run.id, 1)

    assert length(Flows.get_tasks_by_name("mapped", run.id)) == 2
  end

  test "reuses a concurrently created terminal mapped instance during expansion", %{run: run} do
    params = [%{"model" => "a"}, %{"model" => "b"}]

    task_fixture(%{
      run_id: run.id,
      name: "source",
      status: :succeeded,
      result: %{"gust_task_items" => params}
    })

    dag_def =
      definition(%{
        "mapped" => task_options(upstream: ["source"], map_over: :source)
      })

    Gust.DAGTaskExpanderMock
    |> expect(:expand_over, fn ^params, task, run_id, create_fn ->
      task_fixture(%{
        run_id: run_id,
        name: task.name,
        status: :succeeded,
        map_index: 1,
        params: %{"previous" => true}
      })

      MapOver.expand_over(params, task, run_id, create_fn)
    end)

    assert [
             {:ok, %Flows.Task{map_index: 0, params: %{"model" => "a"}}},
             {:ok,
              %Flows.Task{
                id: second_id,
                status: :succeeded,
                map_index: 1,
                params: %{"model" => "b"}
              }}
           ] = StageBuilder.build(["mapped"], run.id, dag_def)

    assert %Flows.Task{id: ^second_id, status: :succeeded} =
             Flows.get_task_by_name("mapped", run.id, 1)

    assert length(Flows.get_tasks_by_name("mapped", run.id)) == 2
  end

  defp definition(tasks), do: %Definition{tasks: tasks}

  defp task_options(opts \\ []) do
    %{
      upstream: opts |> Keyword.get(:upstream, []) |> MapSet.new(),
      store_result: false,
      map_over: Keyword.get(opts, :map_over),
      wait_for: nil,
      skip_if: nil
    }
  end
end
