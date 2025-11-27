defmodule DAG.Loader.WorkerTest do
  alias Gust.Flows
  use Gust.DataCase, async: false
  import Gust.FlowsFixtures
  import ExUnit.CaptureLog
  import Gust.FSHelpers
  alias Gust.DAG.Loader.Worker, as: Loader

  import Mox

  setup :verify_on_exit!
  setup :set_mox_from_context

  setup do
    dag_folder = make_rand_dir!("dags")
    name = "valid_dag_less_than_jake"
    found_dag = dag_fixture(%{name: name})
    found_dag_id = found_dag.id

    dag_def = %Gust.DAG.Definition{
      mod: MockDagMod,
      name: found_dag.name,
      options: []
    }

    Gust.DAGParserMock
    |> expect(:parse_folder, fn ^dag_folder ->
      [
        {name, {:ok, dag_def}}
      ]
    end)

    Gust.DAGSchedulerMock
    |> expect(:schedule, fn %{^found_dag_id => {:ok, ^dag_def}} -> [:ok] end)

    Gust.DAGRunRestarterMock
    |> expect(:restart_dags, fn %{^found_dag_id => {:ok, ^dag_def}} -> [] end)

    %{dag_folder: dag_folder, found_dag_id: found_dag_id, dag_def: dag_def}
  end

  test "log DagLoader created and removed dags", %{
    dag_folder: dag_folder,
    found_dag_id: found_dag_id,
    dag_def: dag_def
  } do
    {_, log} =
      with_log(fn ->
        {:ok, pid} = start_supervised({Loader, %{dags_folder: dag_folder}})
        ref = Process.monitor(pid)
        refute_receive {:DOWN, ^ref, :process, ^pid, :normal}, 200
      end)

    assert log =~ "FOUND DAG: valid_dag_less_than_jake"

    assert %{^found_dag_id => {:ok, ^dag_def}} = Loader.get_definitions()
    assert {:ok, ^dag_def} = Loader.get_definition(found_dag_id)
  end

  describe "handle_info/1" do
    test "broadcast dag_def when file is reloaded", %{
      dag_folder: dag_folder,
      dag_def: dag_def
    } do
      dag_name = dag_def.name
      Gust.PubSub.subscribe_file(dag_name)
      new_dag_name = "new_dag_name"
      Gust.PubSub.subscribe_file(new_dag_name)

      {_, log} =
        with_log(fn ->
          {:ok, pid} = start_supervised({Loader, %{dags_folder: dag_folder}})
          ref = Process.monitor(pid)
          refute_receive {:DOWN, ^ref, :process, ^pid, :normal}, 200

          send(pid, {dag_name, {:ok, dag_def}, "reload"})

          assert_receive {:dag, :file_updated,
                          %{dag_name: ^dag_name, parse_result: {:ok, ^dag_def}, action: "reload"}},
                         200

          dag = Flows.get_dag_by_name(dag_name)
          assert Loader.get_definitions() == %{dag.id => {:ok, dag_def}}

          new_def = %Gust.DAG.Definition{name: new_dag_name}
          send(pid, {new_dag_name, {:ok, new_def}, "reload"})

          assert_receive {:dag, :file_updated,
                          %{
                            dag_name: ^new_dag_name,
                            parse_result: {:ok, ^new_def},
                            action: "reload"
                          }},
                         200

          new_dag = Flows.get_dag_by_name(new_dag_name)

          assert Loader.get_definitions() == %{
                   dag.id => {:ok, dag_def},
                   new_dag.id => {:ok, new_def}
                 }
        end)

      assert log =~ "CREATED DAG: #{new_dag_name}"
    end

    test "broadcast error when file is reloaded and parse fails", %{
      dag_folder: dag_folder,
      dag_def: dag_def
    } do
      dag_name = dag_def.name
      Gust.PubSub.subscribe_file(dag_name)
      error = {[], "ops", ""}

      {pid, _log} =
        with_log(fn ->
          {:ok, pid} = start_supervised({Loader, %{dags_folder: dag_folder}})
          ref = Process.monitor(pid)
          refute_receive {:DOWN, ^ref, :process, ^pid, :normal}, 200
          pid
        end)

      send(pid, {"not_an_existing_dag", {:error, error}, "reload"})
      send(pid, {dag_name, {:error, error}, "reload"})

      assert_receive {:dag, :file_updated,
                      %{dag_name: ^dag_name, parse_result: {:error, ^error}, action: "reload"}},
                     200

      dag = Flows.get_dag_by_name(dag_name)
      assert Loader.get_definitions() == %{dag.id => {:error, error}}
    end

    test "delete dag when file is removed", %{
      dag_folder: dag_folder,
      dag_def: dag_def
    } do
      dag_name = dag_def.name
      Gust.PubSub.subscribe_file(dag_name)

      {pid, _log} =
        with_log(fn ->
          {:ok, pid} = start_supervised({Loader, %{dags_folder: dag_folder}})
          ref = Process.monitor(pid)
          refute_receive {:DOWN, ^ref, :process, ^pid, :normal}, 200
          pid
        end)

      send(pid, {dag_name, {:error, nil}, "removed"})

      assert_receive {:dag, :file_updated,
                      %{dag_name: ^dag_name, parse_result: {:error, nil}, action: "removed"}},
                     200

      assert Flows.get_dag_by_name(dag_name) == nil
      assert Loader.get_definitions() == %{}
    end
  end
end
