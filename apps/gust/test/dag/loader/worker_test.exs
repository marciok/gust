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

    # Create an actual DAG file so the Folder source can find it
    dag_file = Path.join(dag_folder, "#{name}.ex")
    File.write!(dag_file, "defmodule MockDagMod do\nend")

    # Mock the parser adapter to return the dag_def when parsing this file
    Gust.DAGParserAdapterMock
    |> stub(:extensions, fn -> [".ex"] end)
    |> stub(:parse_file, fn ^dag_file ->
      {:ok, dag_def}
    end)

    # Set the dags_folder and parser adapter in application environment for the Folder DAG source
    original_dags_folder = Application.get_env(:gust, :dags_folder)
    original_dag_adapter = Application.get_env(:gust, :dag_adapter)

    Application.put_env(:gust, :dags_folder, dag_folder)

    Application.put_env(:gust, :dag_adapter,
      elixir: %{
        parser: Gust.DAGParserAdapterMock,
        runtime: Gust.DAG.Runtime.Adapters.Elixir,
        task_worker: Gust.DAG.TaskWorker.Adapters.Elixir
      }
    )

    on_exit(fn ->
      # Reset environment variables
      if original_dags_folder do
        Application.put_env(:gust, :dags_folder, original_dags_folder)
      else
        Application.delete_env(:gust, :dags_folder)
      end

      if original_dag_adapter do
        Application.put_env(:gust, :dag_adapter, original_dag_adapter)
      else
        Application.delete_env(:gust, :dag_adapter)
      end
    end)

    %{dag_folder: dag_folder, found_dag_id: found_dag_id, dag_def: dag_def}
  end

  test "loads DAGs from folder on startup", %{
    dag_folder: dag_folder,
    found_dag_id: found_dag_id,
    dag_def: dag_def
  } do
    {:ok, pid} = start_supervised({Loader, %{dags_folder: dag_folder}})
    ref = Process.monitor(pid)
    refute_receive {:DOWN, ^ref, :process, ^pid, :normal}, 200

    # Verify that the DAG was loaded
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
