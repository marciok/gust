defmodule HelloWorld do
  # Schedule is optional, if you change, make sure to restart the server 
  # in order to update the cron job.
  use Gust.DSL #, schedule: "* * * * *"
  require Logger

  task :first_task, downstream: [:second_task], save: true do
    greetings = "Hi from first_task"
    Logger.info(greetings)
    # The return value must be a map when save is true
    %{result: greetings}
  end

  task :second_task, ctx: %{run_id: run_id} do
    task = Gust.Flows.get_task_by_name_run("first_task", run_id)
    Logger.info(task.result)
  end
end
