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

      def start_link(%{task: task} = args) do
        GenServer.start_link(__MODULE__, args, name: via_tuple(task_name(task)))
      end

      defp task_name(task) do
        suffix = if task.map_index, do: "_#{task.map_index}", else: ""

        "task_#{task.id}#{suffix}"
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
    end
  end
end
