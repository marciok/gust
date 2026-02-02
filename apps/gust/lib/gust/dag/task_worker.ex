defmodule Gust.DAG.TaskWorker do
  @moduledoc false

  defmacro __using__(_opts) do
    quote do
      use GenServer
      alias Gust.DAG

      @impl true
      def init(init_arg) do
        {:ok, init_arg, {:continue, :init_run}}
      end

      def start_link(args) do
        GenServer.start_link(__MODULE__, args, name: via_tuple("task_#{args[:task].id}"))
      end

      def child_spec(args) do
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, [args]},
          restart: :temporary,
          type: :worker
        }
      end

      @impl true
      def handle_continue(:init_run, state) do
        send(self(), :run)

        {:noreply, state}
      end

      defp via_tuple(name) do
        {:via, Registry, {Gust.Registry, name}}
      end

      defp try_run(mod, fun_name, args, store_result) do
        apply_and_validate(mod, fun_name, args, store_result)
      rescue
        e -> {:error, e}
      end

      defp apply_and_validate(mod, fun_name, args, store_result) do
        result = apply(mod, fun_name, args)

        if store_result && !is_map(result) do
          raise "Task returned #{inspect(result)} but store_result requires a map"
        else
          {:ok, result}
        end
      end
    end
  end
end
