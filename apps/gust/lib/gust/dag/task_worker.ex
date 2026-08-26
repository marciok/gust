defmodule Gust.DAG.TaskWorker do
  @moduledoc false

  def registry_name(%{id: id, map_index: map_index}) do
    suffix = if map_index, do: "_#{map_index}", else: ""
    "task_#{id}#{suffix}"
  end

  defmacro __using__(_opts) do
    quote do
      use GenServer
      alias Gust.DAG
      alias Gust.DAG.Runner.TaskExecution
      alias Gust.DAG.TaskWorker

      defguardp normal_exit?(reason)
                when reason in [:normal, :shutdown] or
                       (is_tuple(reason) and tuple_size(reason) == 2 and
                          elem(reason, 0) == :shutdown)

      @impl true
      def init(%{task: task} = init_arg) do
        Process.flag(:trap_exit, true)
        task = TaskExecution.update_status!(task, :running)

        {:ok, %{init_arg | task: task}, {:continue, :init_run}}
      end

      def start_link(%{task: task} = args) do
        GenServer.start_link(__MODULE__, args, name: via_tuple(TaskWorker.registry_name(task)))
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

      @impl true
      def handle_info(
            {:EXIT, _pid, reason},
            %{task: task, owner_pid: owner_pid} = state
          )
          when not normal_exit?(reason) do
        send(owner_pid, {:task_result, exit_error(reason), task.id, :error})

        {:stop, :normal, state}
      end

      defp via_tuple(name) do
        {:via, Registry, {Gust.Registry, name}}
      end

      defp exit_error(reason) do
        %RuntimeError{message: "Linked process exited: #{inspect(reason)}"}
      end
    end
  end
end
