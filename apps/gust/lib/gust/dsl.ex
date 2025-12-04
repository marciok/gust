defmodule Gust.DSL do
  @moduledoc """
  The Gust DSL is how you turn a module into a DAG.  
  When you add `use Gust.DSL` to a module in the `dags/` folder, Gust automatically detects it and creates a DAG based on the file name.

  You can configure a schedule, define callbacks, and in the `dev` environment the code is automatically reloaded when files change.

  After enabling the DSL, use `task` definitions to declare the steps that should be executed.

  ## Example

      defmodule HelloWorld do
        # `schedule` and `on_finished_callback` are optional.
        # Note: if you change `schedule`, restart the server to update the cron job.
        use Gust.DSL, schedule: "* * * * *", on_finished_callback: :notify_something

        # Gust logs are stored and displayed through GustWeb via Logger.
        require Logger

        # Gust.Flows is used to query Dag, Run, and Task.
        alias Gust.Flows

        def notify_something(status, run) do
          dag = Flows.get_dag!(run.dag_id)
          message = "DAG: \#{dag.name}; completed with status: \#{status}"
          Logger.info(message)
        end

        task :first_task, downstream: [:second_task], store_result: true do
          greetings = "Hi from first_task"
          Logger.info(greetings)

          # The return value must be a map when `store_result` is true.
          %{result: greetings}
        end

        task :second_task, ctx: %{run_id: run_id} do
          task = Flows.get_task_by_name_run("first_task", run_id)
          Logger.info(task.result)
        end
      end

  ## Parameters

    * `schedule` - A valid cron expression string.
    * `on_finished_callback` - The name of the function to be called.
  """

  defmacro __using__(dag_options) do
    quote do
      import unquote(__MODULE__), only: [task: 2, task: 3]

      Module.register_attribute(__MODULE__, :dag_tasks, accumulate: true)

      def __dag_options__, do: unquote(dag_options)

      @before_compile unquote(__MODULE__)
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      def __dag_tasks__, do: @dag_tasks
    end
  end

  @doc """
  Defines a task in the DAG.

  ## Parameters

    * `name` — The name of the task (atom).
    * `opts_and_ctx` — A keyword list of options and an optional context pattern.
    * `block` — The code block executed when the task runs.

  ## Task Options

    * `:downstream` — A list of task names (atoms) to run after this task completes.
    * `:store_result` — When true, the task's return value will be persisted.
        * Note: If enabled, the return value **must be a map**.
    * `:ctx` — A pattern that will be matched against the context passed to the task.
        * Defaults to: `%{run_id: run_id}`.

  ## Example

      task :my_task, ctx: %{run_id: run_id} do
        IO.inspect(run_id)
      end

      task :first, downstream: [:second] do
        :ok
      end

      task :persist_result, store_result: true do
        %{result: :ok}
      end

  When using `store_result: true`, the return value **must** be a map so it can be merged into the overall DAG results.
  """
  defmacro task(name, opts_and_ctx, do: block) do
    {ctx_pattern, opts} = Keyword.pop(opts_and_ctx, :ctx)
    ctx_pattern = ctx_pattern || quote do: %{run_id: run_id}

    quote do
      @dag_tasks {unquote(name), unquote(opts)}

      def unquote(name)(ctx) do
        unquote(ctx_pattern) = ctx
        unquote(block)
      end
    end
  end

  @doc """
  Defines a task in the DAG without options or explicit context matching.

  ## Parameters

    * `name` - The name of the task (atom).
    * `block` - The code block to execute for the task.

  ## Example

      task :simple_task do
        IO.puts "Hello"
      end
  """
  defmacro task(name, do: block) do
    quote do
      @dag_tasks {unquote(name), []}

      def unquote(name)(ctx) do
        unquote(block)
      end
    end
  end
end
