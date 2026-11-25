defmodule GustPy.Executor.UV do
  @moduledoc """
  Runs `uv` to parse Python DAGs and execute their tasks.

  By default `uv` inherits the environment of the Elixir runtime, since DAG
  code is trusted. With `config :gust_py, :clear_env, true` it starts with a
  cleared environment instead, so DAG code cannot read values such as
  `DATABASE_URL` or `SECRET_KEY_BASE`, or leak them into task logs.

  A cleared environment keeps only what `uv` and Python need: `PATH`, `HOME`,
  the user, shell, temp dir, timezone, locale, XDG directories, TLS certificate
  and proxy settings, and any `UV_*` variable. Pass more by name with
  `config :gust_py, :env_passthrough, ["AWS_PROFILE"]`.
  """

  @behaviour GustPy.Executor

  @working_dir_flag "UV_WORKING_DIR"

  @passthrough_env ~w(
    PATH HOME USER LOGNAME SHELL TMPDIR TZ
    LANG LANGUAGE LC_ALL LC_CTYPE
    XDG_CACHE_HOME XDG_CONFIG_HOME XDG_DATA_HOME
    SSL_CERT_FILE SSL_CERT_DIR REQUESTS_CA_BUNDLE
    HTTP_PROXY HTTPS_PROXY NO_PROXY http_proxy https_proxy no_proxy
  )

  @impl true
  def start_task(dag_def, task_name, context) do
    args = task_args(dag_def, task_name, context)
    run_exec(args)
  end

  defp task_args(dag_def, task_name, task_context) do
    [
      "run",
      "gust",
      "task",
      "run",
      "--file",
      dag_def.file_path,
      "--dag",
      dag_def.mod,
      "--task",
      task_name,
      "--ctx-json",
      Jason.encode!(task_context)
    ]
  end

  @impl true
  def run(args_list) do
    case exec() do
      {:error, error} ->
        {:error, error}

      {:ok, uv} ->
        System.cmd(uv, ["run", "gust" | args_list], env: cmd_env(clear_env?()))
    end
  end

  def run_exec(args_list) do
    {:ok, uv} = exec()

    {:ok, _exec_pid, os_pid} =
      :exec.run([uv | args_list], [
        :stdin,
        {:stdout, self()},
        {:stderr, self()},
        :monitor,
        {:group, 0},
        :kill_group,
        {:kill_timeout, 5},
        {:env, exec_env(clear_env?())}
      ])

    os_pid
  end

  defp exec_env(false), do: [{@working_dir_flag, working_dir()}]
  defp exec_env(true), do: [:clear | Map.to_list(cleared_env())]

  defp cmd_env(false), do: %{@working_dir_flag => working_dir()}

  defp cmd_env(true) do
    env = cleared_env()
    unset = for {name, _value} <- System.get_env(), not Map.has_key?(env, name), do: {name, nil}

    Map.to_list(env) ++ unset
  end

  defp cleared_env do
    allowed = MapSet.new(@passthrough_env ++ Application.get_env(:gust_py, :env_passthrough, []))

    System.get_env()
    |> Map.filter(fn {name, _value} ->
      MapSet.member?(allowed, name) or String.starts_with?(name, "UV_")
    end)
    |> Map.put(@working_dir_flag, working_dir())
  end

  defp clear_env?, do: Application.get_env(:gust_py, :clear_env, false)

  defp working_dir do
    dag_folder = Application.get_env(:gust, :dags_folder)
    Application.get_env(:gust_py, :uv_working_dir, dag_folder)
  end

  defp exec do
    uv = System.find_executable("uv")
    if uv, do: {:ok, uv}, else: {:error, :uv_not_found}
  end
end
