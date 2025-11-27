defmodule DAG.Scheduler.WorkerTest do
  import Crontab.CronExpression
  use Gust.DataCase
  import Gust.FlowsFixtures
  import Gust.FSHelpers
  alias Gust.DAG.Cron
  alias Gust.DAG.Scheduler.Worker

  import Mox

  setup :verify_on_exit!
  setup :set_mox_from_context

  describe "handle_call/2 when {:load_dags, dags} is passed" do
    setup do
      start_link_supervised!(Cron)
      name = "blink_182"
      dag = dag_fixture(%{name: name})
      dag_folder = make_rand_dir!("dags")

      %{dag: dag, folder: dag_folder}
    end

    test "do not add task for dag with errors", %{dag: dag} do
      name = dag.name

      dag_def = %Gust.DAG.Definition{
        mod: MockDagMod,
        name: name,
        error: %CompileError{description: "opsss"},
        options: [schedule: "* * * * *"]
      }

      start_link_supervised!({Gust.DAG.Scheduler.Worker, {}})

      Worker.schedule(%{dag.id => dag_def})

      assert Cron.find_job(String.to_atom(name)) == nil
    end

    test "do not add errored dag", %{dag: dag} do
      name = dag.name

      start_link_supervised!({Gust.DAG.Scheduler.Worker, {}})

      Worker.schedule(%{dag.id => {:error, {}}})

      assert Cron.find_job(String.to_atom(name)) == nil
    end

    test "do not add task for dag without scheduler", %{dag: dag} do
      name = dag.name

      dag_def = %Gust.DAG.Definition{
        mod: MockDagMod,
        name: name,
        options: []
      }

      start_link_supervised!({Gust.DAG.Scheduler.Worker, {}})

      Worker.schedule(%{dag.id => {:ok, dag_def}})

      assert Cron.find_job(String.to_atom(name)) == nil
    end

    test "add task for dag with scheduler", %{dag: dag} do
      name = dag.name

      dag_def = %Gust.DAG.Definition{
        mod: MockDagMod,
        name: name,
        error: %{},
        options: [schedule: "* * * * *"]
      }

      start_link_supervised!({Gust.DAG.Scheduler.Worker, {}})
      atom_name = String.to_atom(name)
      schedule = ~e[* * * * *]

      start_dag_task = {
        Gust.DAG.RunRestarter,
        :start_dag,
        [dag.id]
      }

      [:ok] = Worker.schedule(%{dag.id => {:ok, dag_def}})

      assert %Quantum.Job{name: ^atom_name, schedule: ^schedule, task: ^start_dag_task} =
               Cron.find_job(String.to_atom(name))
    end
  end
end
