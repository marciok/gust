defmodule FlowsTest do
  use Gust.DataCase
  alias Gust.Flows
  import Gust.FlowsFixtures

  describe "dags" do
    alias Gust.Flows.Dag

    test "list_dags/0 returns all dags" do
      dag = dag_fixture()
      assert Flows.list_dags() == [dag]
    end

    test "create_dag/1 with valid data creates a dag" do
      valid_attrs = %{name: "some_name"}

      assert {:ok, %Dag{} = dag} = Flows.create_dag(valid_attrs)
      assert dag.name == "some_name"
    end

    test "create_dag/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Flows.create_dag(%{name: "invalid name"})
    end

    test "get_dag_by_name/1 return dag with name" do
      name = "my_name"
      dag = dag_fixture(%{name: name})
      assert Flows.get_dag_by_name(name) == dag
    end

    test "delete_dag!/1 delete dag" do
      name = "my_name"
      dag = dag_fixture(%{name: name})
      Flows.delete_dag!(dag)
      assert Flows.list_dags() == []
    end

    test "toggle_enabled/1 toggles the enabled field" do
      dag = dag_fixture(%{enabled: true})

      {:ok, updated_dag} = Flows.toggle_enabled(dag)

      assert updated_dag.enabled == false

      {:ok, toggled_back_dag} = Flows.toggle_enabled(updated_dag)

      assert toggled_back_dag.enabled == true
    end

    test "get_dag_with_runs!/1 return dag with runs" do
      name = "my_name"
      dag = dag_fixture(%{name: name})
      run = run_fixture(%{dag_id: dag.id})

      assert [^run] = Flows.get_dag_with_runs!(dag.id).runs
    end

    test "delete_not_found_ids/1 with empty list returns {:ok, 0}" do
      dag = dag_fixture(%{name: "my_dag"})

      result = Flows.delete_not_found_ids([])

      assert result == {:ok, 0}

      assert Flows.list_dags() == [dag]
    end

    test "get_dag_with_runs_and_tasks!/1 returns dag with ordered runs and tasks" do
      name = "my_name"
      dag = dag_fixture(%{name: name})

      run_3 = run_fixture(%{dag_id: dag.id, inserted_at: ~N[2022-01-01 00:00:00]})
      run_2 = run_fixture(%{dag_id: dag.id, inserted_at: ~N[2021-01-01 00:00:00]})
      run_1 = run_fixture(%{dag_id: dag.id, inserted_at: ~N[2020-01-01 00:00:00]})

      task_fixture(%{run_id: run_1.id, name: "my_task"})

      page_size = 2
      offset = 0

      run_ids =
        for run <- Flows.get_dag_with_runs_and_tasks!(name, limit: page_size, offset: offset).runs do
          run.id
        end

      assert run_ids == [run_3.id, run_2.id]
    end
  end

  describe "run" do
    alias Gust.Flows.Run

    test "create_run/1 with valid data creates a run" do
      dag = dag_fixture(%{name: "some_name"})

      assert {:ok, %Run{} = run} = Flows.create_run(%{dag_id: dag.id})
      assert ^dag = (run |> Repo.preload(:dag)).dag
    end

    test "update_run_status/2 with valid data updates run" do
      dag = dag_fixture(%{name: "some_name"})

      new_status = :succeeded
      run = run_fixture(%{dag_id: dag.id})
      {:ok, %Run{status: status}} = Flows.update_run_status(run, new_status)
      assert status == new_status
    end

    test "get_run!/1 returns the run by id" do
      dag = dag_fixture(%{name: "some_name"})
      %Run{id: id} = run_fixture(%{dag_id: dag.id})

      assert %Run{id: ^id} = Flows.get_run!(id)
    end

    test "get_run_with_tasks!/1 preloads the :tasks association" do
      dag = dag_fixture(%{name: "some_name"})
      %Run{id: id} = run_fixture(%{dag_id: dag.id})

      run = Flows.get_run_with_tasks!(id)

      assert Ecto.assoc_loaded?(run.tasks)
      assert is_list(run.tasks)
    end
  end

  describe "log" do
    test "get_log!/1" do
      dag = dag_fixture(%{name: "some_name"})
      run = run_fixture(%{dag_id: dag.id})
      task = task_fixture(%{run_id: run.id, name: "my_task"})

      log = log_fixture(%{task_id: task.id, content: "hello", level: "info", attempt: 1})

      assert ^log = Flows.get_log!(log.id)
    end
  end

  describe "task" do
    alias Gust.Flows.Task

    test "create_task/1 with valid data creates a task" do
      dag = dag_fixture(%{name: "some_name"})
      run = run_fixture(%{dag_id: dag.id})
      task_name = "busted"

      assert {:ok, _task} = Flows.create_task(%{run_id: run.id, name: task_name})
    end

    test "update_task_status/2 with valid data updates task" do
      dag = dag_fixture(%{name: "some_name"})

      new_status = :succeeded
      run = run_fixture(%{dag_id: dag.id})
      task = task_fixture(%{run_id: run.id, name: "my_task"})

      {:ok, %Task{status: status}} = Flows.update_task_status(task, new_status)
      assert status == new_status
    end

    test "get_task_with_logs!/1 returns the task with preloaded logs" do
      dag = dag_fixture(%{name: "some_name"})
      run = run_fixture(%{dag_id: dag.id})
      task = task_fixture(%{run_id: run.id, name: "my_task"})

      # attach a couple of logs to this task
      log1 = log_fixture(%{task_id: task.id, content: "hello", level: "info", attempt: 1})
      log2 = log_fixture(%{task_id: task.id, content: "bye", level: "warn", attempt: 1})
      task_id = task.id

      fetched = Flows.get_task_with_logs!(task.id)
      assert %Task{id: ^task_id} = fetched

      assert Enum.map(fetched.logs, & &1.id) |> MapSet.new() ==
               MapSet.new([log1.id, log2.id])
    end

    test "get_task_by_name_run_with_logs/2 returns the task by name/run and preloads logs" do
      dag = dag_fixture(%{name: "some_name"})
      run = run_fixture(%{dag_id: dag.id})
      task = task_fixture(%{run_id: run.id, name: "target_task"})
      task_id = task.id

      # logs for the target task
      log_a = log_fixture(%{task_id: task.id, content: "A", level: "info", attempt: 1})
      log_b = log_fixture(%{task_id: task.id, content: "B", level: "debug", attempt: 2})

      # noise: another task + log that should not be included
      other_task = task_fixture(%{run_id: run.id, name: "other_task"})
      _other_log = log_fixture(%{task_id: other_task.id, content: "C", level: "warn", attempt: 1})

      fetched = Flows.get_task_by_name_run_with_logs("target_task", run.id)
      assert %Task{id: ^task_id} = fetched

      assert Enum.map(fetched.logs, & &1.id) |> MapSet.new() ==
               MapSet.new([log_a.id, log_b.id])
    end
  end

  describe "secret" do
    setup do
      name = "MY_DIRTY_LITTLE_SECRET"
      secret = secret_fixture(%{name: name, value: "do not tell", value_type: :string})
      %{secret: secret, name: name}
    end

    test "list_secrets/0", %{secret: secret} do
      assert [^secret] = Flows.list_secrets()
    end

    test "delete_secret/1", %{secret: secret} do
      Flows.delete_secret(secret)

      assert_raise Ecto.NoResultsError, fn -> Flows.get_secret!(secret.id) end
    end

    test "get_secret_by_name/1 return secret with name", %{secret: secret, name: name} do
      assert Flows.get_secret_by_name(name) == secret
    end

    test "get_secret!/1", %{secret: secret} do
      assert Flows.get_secret!(secret.id) == secret
    end

    test "update_secret/1", %{secret: secret} do
      new_value = "I told"
      Flows.update_secret(secret, %{value: new_value})
      assert ^new_value = Flows.get_secret!(secret.id).value
    end

    test "change_secret/2 returns a secret changeset", %{secret: secret} do
      changeset = Flows.change_secret(secret)

      assert %Ecto.Changeset{} = changeset
      assert changeset.data == secret
      assert changeset.valid?
    end

    test "change_secret/2 applies attribute changes without persisting", %{secret: secret} do
      attrs = %{value: "less secret"}
      old_value = secret.value

      changeset = Flows.change_secret(secret, attrs)

      assert changeset.valid?
      assert changeset.changes.value == "less secret"

      assert ^old_value = Flows.get_secret!(secret.id).value
    end
  end
end
