# Writing DAGs

## Elixir DAGs

Elixir DAGs are plain Elixir modules that `use Gust.DSL`. Each `task` block declares
its downstream tasks, and Gust resolves execution order from that graph.

```elixir
defmodule HelloWorld do
  @moduledoc false
  # `schedule` and `on_finished_callback` are optional.
  use Gust.DSL, schedule: "* * * * *", on_finished_callback: :notify_something

  # Gust logs are stored and displayed through GustWeb via Logger.
  require Logger

  # Gust.Flows is used to query Dag, Run, and Task.
  alias Gust.Flows

  def notify_something(status, run) do
    dag = Flows.get_dag!(run.dag_id)
    message = "DAG: #{dag.name}; completed with status: #{status}"
    Logger.info(message)
  end

  def skip_first_task?(%{run_id: run_id}) do
    run = Flows.get_run!(run_id)
    Map.get(run.params, "skip_first_task", false)
  end

  task :first_task, downstream: [:second_task], save: true, skip_if: :skip_first_task? do
    greetings = "Hi from first_task"
    Logger.info(greetings)
    greetings = ["Hello!", "Olá!", "¡Hola!", "Bonjour!"]

    # You can get secrets created on the Web UI
    secret = Flows.get_secret_by_name("SUPER_SECRET")

    if secret do
      Logger.warning("I know your secret: #{secret.value}")
    end

    # The return value must be a map or a list when `save` is true.
    greetings
  end

  task :second_task,
    downstream: [:final_task],
    ctx: %{params: params},
    map_over: :first_task,
    save: true do
    message = "#{params["item"]} World!"
    Logger.warning(message)
    %{greeting: message}
  end

  task :final_task, ctx: %{run_id: run_id} do
    # Getting tasks results
    second_tasks = Flows.get_tasks_by_name("second_task", run_id)

    Enum.each(second_tasks, fn task ->
      Logger.warning(inspect(task.result))
    end)
  end
end
```

## Shell DAGs

Shell DAGs are YAML files in your DAG folder. The file name becomes the DAG name,
so `backup_files.yml` creates the `backup_files` DAG:

```yaml
# `schedule` and `on_finished_callback` are optional.
schedule: "0 3 * * *"

tasks:
  - name: backup_data
    run: "tar -czf backup.tar.gz /data"
    cd: "/var/backups"
    downstream: [upload_backup]
    save: true

  - name: upload_backup
    run: "aws s3 cp backup.tar.gz s3://my-bucket/"
    cd: "/var/backups"
    env:
      AWS_PROFILE: production
```

Each task runs its `run` command in a shell, and parallel execution is automatic
for tasks without dependencies. Shell DAGs are useful when the workflow is mostly
command-line actions, and they support task metadata such as `save`, `env`, `cd`,
and templated values from run params and secrets.

See [the shell DAG guide](../../gust_shell/guides/writing_shell_dags.md) for the
full reference.

## Python DAGs

Python DAGs let you reuse existing Python workflow definitions with the `gust`
Python package. Tasks are methods decorated with `@task`, and the DAG class can
still define scheduling and callbacks:

```python
from gust import Dag, task, log, get_secret_by_name

class HelloWorld(Dag):

    def __init__(self):
        super().__init__(schedule="* * * * *", on_finished_callback="notify_something")

    def notify_something(self, status, run):
        print("DAG is done!")

    @task(downstream=["second_task"], save=True)
    def first_task(self, ctx):
        secret = get_secret_by_name("SECRET")
        log(f"I know your secret: {secret}")
        return {"result": "Hi!"}

    @task()
    def second_task(self, ctx):
        print("next step")
```

Python DAGs are a good fit when your team already has Python-based orchestration
logic or wants to keep workflow definitions close to the code that produces their
inputs and outputs.

See [the Python DAG guide](../../gust_py/guides/writing_python_dags.md) for the
full reference.

## Features used above

- **Scheduling** — `schedule:` accepts a cron expression; DAGs without one are
  triggered manually or via the HTTP API.
- **`:map_over`** — creates one task instance per item in an upstream task's
  saved result, fanning execution out in parallel.
- **`:skip_if`** — conditionally skips a task; any task depending on a skipped
  task is skipped too.
- **`:save`** — persists a task's return value (a map or a list) so downstream
  tasks and the Web UI can read it back through `Gust.Flows`.
- **`on_finished_callback`** — a function on the DAG module invoked once the
  run finishes, with its final status.

See `Gust.DSL` for the full macro reference.

## Reusable actions

Use `task_action` when the operation should be reusable across DAGs. Static arguments are
declared in a tuple; the argument expression is still evaluated when the task executes:

```elixir
task_action :send_email,
  {MyApp.Actions.SendEmail, [template: "welcome", recipient: "ops@example.com"]},
  downstream: [:record_delivery],
  save: true
```

Arguments can instead be computed at runtime with the same `ctx:` convention as `task`:

```elixir
task_action :send_email, MyApp.Actions.SendEmail,
  ctx: %{params: params},
  save: true do
  [template: params["template"], recipient: params["recipient"]]
end
```

An action implements `Gust.Action`. It receives the resolved keyword arguments and the full task
context, and its return value is the task return value:

```elixir
defmodule MyApp.Actions.Echo do
  @behaviour Gust.Action

  @impl true
  def execute(args, _context) do
    %{message: Keyword.fetch!(args, :message)}
  end
end
```

Action argument and execution failures follow the ordinary task failure and retry behavior.
When `save: true`, the action must return a map or list accepted by Gust's normal result
persistence rules.
