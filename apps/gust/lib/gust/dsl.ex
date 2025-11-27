defmodule Gust.DSL do
  @moduledoc """
  A DSL for defining Directed Acyclic Graphs (DAGs) of tasks.

  This module provides macros to define tasks and their dependencies in a declarative way.
  It is intended to be `use`d by modules that define DAGs.

  ## Example

      defmodule MyDag do
        use Gust.DSL,
          schedule: "* * * * *"

        task :step_1 do
          # logic for step 1
        end

        task :step_2, ctx: %{run_id: run_id} do
          # logic for step 2 using run_id
        end
      end
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

    * `name` - The name of the task (atom).
    * `opts_and_ctx` - A keyword list of options and context pattern matching.
      * `:ctx` - A pattern to match against the context passed to the task. Defaults to `%{run_id: run_id}`.
    * `block` - The code block to execute for the task.

  ## Example

      task :my_task, ctx: %{run_id: run_id} do
        IO.inspect(run_id)
      end
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
