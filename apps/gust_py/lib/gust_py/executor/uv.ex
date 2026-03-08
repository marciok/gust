defmodule GustPy.Executor.UV do
  @moduledoc false

  @behaviour GustPy.Executor

  @working_dir_flag "UV_WORKING_DIR"

  @impl true
  def start_task_via_port(dag_def, task_name, context) do
    args = task_args(dag_def, task_name, context)
    open_port(args)
  end

  defp task_args(dag_def, task_name, task_context) do
    [
      ~c"run",
      ~c"gust",
      ~c"task",
      ~c"run",
      ~c"--file",
      dag_def.file_path,
      ~c"--dag",
      dag_def.mod,
      ~c"--task",
      task_name,
      ~c"--ctx-json",
      Jason.encode!(task_context)
    ]
  end

  @impl true
  def run(args_list) do
    System.cmd(exec(), ["run", "gust" | args_list], env: %{@working_dir_flag => working_dir()})
  end

  def open_port(args_list) do
    worging_dir = working_dir() |> to_charlist()
    uv = exec() |> to_charlist()

    Port.open({:spawn_executable, uv}, [
      :binary,
      :use_stdio,
      :exit_status,
      {:packet, 4},
      {:env, [{to_charlist(@working_dir_flag), worging_dir}]},
      {:args, args_list}
    ])
  end

  defp working_dir do
    dag_folder = Application.get_env(:gust, :dags_folder)
    Application.get_env(:gust_py, :uv_working_dir, dag_folder)
  end

  defp exec, do: System.find_executable("uv")
end
