defmodule DSLTest do
  use Gust.DataCase

  test "use macro with schedule option" do
    dag_code = """
      defmodule MyValidDagEmpty do
        use Gust.DSL, schedule: "0 17 * * *"

        task :hi do
          # saying hi
          1 + 1
        end

      end
    """

    [{mod, _bin}] = Code.compile_string(dag_code)

    assert mod.__dag_options__() == [schedule: "0 17 * * *"]

    :code.purge(mod)
    :code.delete(mod)
  end

  test "task macro without opts" do
    dag_code = """
      defmodule MyValidDagEmpty do
        use Gust.DSL

        task :hi do
          # saying hi
          1 + 1
        end

      end
    """

    [{mod, _bin}] = Code.compile_string(dag_code)

    assert mod.__dag_tasks__() == [{:hi, []}]

    :code.purge(mod)
    :code.delete(mod)
  end

  test "DAG code can raise a non-recoverable error" do
    dag_code = """
      defmodule NonRecoverableDag do
        use Gust.DSL

        task :hi do
          raise Gust.DAG.NonRecError, "invalid input"
        end
      end
    """

    [{mod, _bin}] = Code.compile_string(dag_code)

    assert_raise Gust.DAG.NonRecError, "invalid input", fn ->
      mod.hi(%{run_id: 123})
    end

    :code.purge(mod)
    :code.delete(mod)
  end

  test "task macro with context option" do
    run_id = 1234
    ctx = %{run_id: 1234}

    dag_code = """
      defmodule MyValidDagEmpty do
        use Gust.DSL

        task :hi, ctx: %{run_id: run_id} do
          run_id
        end

      end
    """

    [{mod, _bin}] = Code.compile_string(dag_code)
    assert mod.__dag_tasks__() == [{:hi, []}]

    # credo:disable-for-next-line Credo.Check.Refactor.Apply
    assert apply(mod, :hi, [ctx]) == run_id

    :code.purge(mod)
    :code.delete(mod)
  end

  test "task macro with save option" do
    dag_code = """
      defmodule MyValidDagEmpty do
        use Gust.DSL

        task :hi, save: true do
          # saying hi
          1 + 1
        end

      end
    """

    [{mod, _bin}] = Code.compile_string(dag_code)

    assert mod.__dag_tasks__() == [{:hi, [store_result: true]}]

    :code.purge(mod)
    :code.delete(mod)
  end

  test "task macro with store_result option" do
    dag_code = """
      defmodule MyValidDagEmpty do
        use Gust.DSL

        task :hi, store_result: true do
          # saying hi
          1 + 1
        end

      end
    """

    [{mod, _bin}] = Code.compile_string(dag_code)

    assert mod.__dag_tasks__() == [{:hi, [store_result: true]}]

    :code.purge(mod)
    :code.delete(mod)
  end

  test "task macro with map_over option and mapped context" do
    dag_code = """
      defmodule MyMappedDag do
        use Gust.DSL

        task :insert_models, map_over: :say_by, ctx: %{params: %{"model" => model}} do
          model
        end
      end
    """

    [{mod, _bin}] = Code.compile_string(dag_code)

    assert mod.__dag_tasks__() == [{:insert_models, [map_over: :say_by]}]
    assert mod.insert_models(%{params: %{"model" => "gpt-5"}}) == "gpt-5"

    :code.purge(mod)
    :code.delete(mod)
  end

  test "task_action invokes static arguments at task runtime" do
    dag_code = """
      defmodule StaticAction do
        @behaviour Gust.Action

        @impl true
        def execute(args, context), do: %{args: args, context: context}
      end

      defmodule StaticActionDag do
        use Gust.DSL

        task_action :run,
          {StaticAction, [message: send(self(), :static_arguments_evaluated)]},
          save: true
      end
    """

    [{action_mod, _}, {dag_mod, _}] = Code.compile_string(dag_code)

    assert dag_mod.run(%{run_id: 12, params: %{}}) == %{
             args: [message: :static_arguments_evaluated],
             context: %{run_id: 12, params: %{}}
           }

    assert_received :static_arguments_evaluated

    :code.purge(dag_mod)
    :code.delete(dag_mod)
    :code.purge(action_mod)
    :code.delete(action_mod)
  end

  test "task_action computes dynamic arguments with the mapped task context" do
    dag_code = """
      defmodule DynamicAction do
        @behaviour Gust.Action

        @impl true
        def execute(args, context), do: {args, context}
      end

      defmodule DynamicActionDag do
        use Gust.DSL

        task_action :run, DynamicAction,
          ctx: %{params: %{"item" => item}},
          map_over: :source do
          [item: item]
        end
      end
    """

    [{action_mod, _}, {dag_mod, _}] = Code.compile_string(dag_code)

    assert dag_mod.run(%{run_id: 34, params: %{"item" => "mapped"}}) ==
             {[item: "mapped"], %{run_id: 34, params: %{"item" => "mapped"}}}

    :code.purge(dag_mod)
    :code.delete(dag_mod)
    :code.purge(action_mod)
    :code.delete(action_mod)
  end

  test "task_action rejects arguments that do not resolve to a keyword list" do
    dag_code = """
      defmodule InvalidArgumentsAction do
        @behaviour Gust.Action
        def execute(args, _context), do: args
      end

      defmodule InvalidArgumentsDag do
        use Gust.DSL
        task_action :run, {InvalidArgumentsAction, :not_a_keyword_list}
      end
    """

    [{action_mod, _}, {dag_mod, _}] = Code.compile_string(dag_code)

    assert_raise ArgumentError, ~r/arguments must resolve to a keyword list/, fn ->
      dag_mod.run(%{run_id: 56, params: %{}})
    end

    :code.purge(dag_mod)
    :code.delete(dag_mod)
    :code.purge(action_mod)
    :code.delete(action_mod)
  end

  test "task macro with wait_for option" do
    dag_code = """
      defmodule MyWaitingDag do
        use Gust.DSL

        task :await_payment, wait_for: "payment_received" do
          :ok
        end
      end
    """

    [{mod, _bin}] = Code.compile_string(dag_code)

    assert mod.__dag_tasks__() == [{:await_payment, [wait_for: "payment_received"]}]

    :code.purge(mod)
    :code.delete(mod)
  end

  test "task macro supports the default scalar map_over item context" do
    dag_code = """
      defmodule MyScalarMappedDag do
        use Gust.DSL

        task :say_bye, map_over: :names, ctx: %{params: %{"item" => item}} do
          item
        end
      end
    """

    [{mod, _bin}] = Code.compile_string(dag_code)

    assert mod.say_bye(%{params: %{"item" => "MARCIO"}}) == "MARCIO"

    :code.purge(mod)
    :code.delete(mod)
  end

  test "task macro with downstream opts" do
    dag_code = """
      defmodule MyValidDagEmpty do
        use Gust.DSL

        task :bye do
          # saying bye
          2 + 2
        end

        task :hi, downstream: [:bye] do
          # saying hi
          1 + 1
        end

      end
    """

    [{mod, _bin}] = Code.compile_string(dag_code)

    assert mod.__dag_tasks__() == [{:hi, [downstream: [:bye]]}, {:bye, []}]

    :code.purge(mod)
    :code.delete(mod)
  end
end
