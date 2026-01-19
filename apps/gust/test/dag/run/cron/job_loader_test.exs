defmodule DAG.Run.Cron.JobLoaderTest do
  import Crontab.CronExpression
  alias Gust.DAG.Scheduler
  use Gust.DataCase
  import Gust.FlowsFixtures
  alias Gust.DAG.Run.Cron.{JobLoader, Scheduler}

  import Mox

  setup :verify_on_exit!
  setup :set_mox_from_context

  describe "handle_continue/2 when :load_jobs is passed" do
    test "schedule jobs for valid dag_defs" do
      start_link_supervised!(Scheduler)
      errored_dag = dag_fixture(%{name: "blink_dag"})

      errored_dag_def = %Gust.DAG.Definition{
        mod: MockDagMod,
        name: errored_dag.name,
        error: %CompileError{description: "opsss"},
        options: [schedule: "* * * * *"]
      }

      dag = dag_fixture(%{name: "less_than_jake_dag"})

      dag_def = %Gust.DAG.Definition{
        mod: MockDagMod,
        name: dag.name,
        error: %{},
        options: [schedule: "* * * * *"]
      }

      dag_without_schedule = dag_fixture(%{name: "the_offspring_dag"})

      dag_def_without_schedule = %Gust.DAG.Definition{
        mod: MockDagMod,
        name: dag_without_schedule.name,
        error: %{},
        options: []
      }

      Gust.DAGLoaderMock
      |> expect(:get_definitions, fn ->
        %{
          dag.id => {:ok, dag_def},
          errored_dag.id => {:ok, errored_dag_def},
          dag_without_schedule.id => {:ok, dag_def_without_schedule}
        }
      end)

      Gust.DAGRunTriggerMock |> expect(:dispatch_run, fn new_run -> new_run end)
      schedule = ~e[* * * * *]
      dag_name = dag.name
      dag_id = dag.id
      Gust.PubSub.subscribe_runs_for_dag(dag_id)

      start_link_supervised!(JobLoader)
      Process.sleep(200)

      assert %Quantum.Job{name: :less_than_jake_dag, schedule: ^schedule, task: _start_dag_task} =
               job =
               Scheduler.find_job(String.to_atom(dag_name))

      assert %Gust.Flows.Run{dag_id: ^dag_id} = run = job.task.()
      run_id = run.id

      assert_receive {:dag, :run_started, %{run_id: ^run_id}}
    end
  end
end
