defmodule GustShell.Parser.Adapter do
  @moduledoc false

  @behaviour Gust.DAG.Parser.Adapter

  alias Gust.DAG.{Definition, Graph}
  alias GustShell.Template

  @dag_opts %{"schedule" => :schedule, "on_finished_callback" => :on_finished_callback}
  @exec_opts %{
    "cd" => :cd,
    "cwd" => :cd,
    "working_dir" => :cd,
    "cgroup" => :cgroup,
    "debug" => :debug,
    "env" => :env,
    "executable" => :executable,
    "group" => :group,
    "kill_timeout" => :kill_timeout,
    "nice" => :nice,
    "pty" => :pty,
    "pty_echo" => :pty_echo,
    "stderr" => :stderr,
    "stdin" => :stdin,
    "stdout" => :stdout,
    "success_exit_code" => :success_exit_code,
    "user" => :user
  }
  @task_opts ~w(name run downstream save store_result) ++ Map.keys(@exec_opts)
  @default_exec_opts [:stdin, :stdout, :stderr, :monitor, {:group, 0}, :kill_group]
  @std_keys ~w(stdin stdout stderr)a

  @impl true
  def extension, do: ".yml"

  @impl true
  def parse_file(file_path) do
    with {:ok, yaml} <- read_yaml(file_path),
         {:ok, definition} <- build_definition(yaml, file_path) do
      {:ok, definition}
    else
      {:error, reason} -> {:error, {[], "invalid shell DAG", inspect(reason)}}
    end
  rescue
    error in ArgumentError ->
      {:error, {[], "invalid shell DAG", Exception.message(error)}}
  end

  defp read_yaml(file_path) do
    {:ok, :glazer_yaml.read_file(file_path)}
  rescue
    error -> {:error, error}
  end

  defp build_definition(yaml, file_path) do
    validate_keys!(yaml, ["tasks" | Map.keys(@dag_opts)])
    entries = Map.get(yaml, "tasks")

    unless is_list(entries), do: raise(ArgumentError, "tasks must be a list")

    tasks = Enum.map(entries, &parse_task!/1)
    names = Enum.map(tasks, &elem(&1, 0))

    if length(names) != length(Enum.uniq(names)),
      do: raise(ArgumentError, "task names must be unique")

    Enum.each(tasks, fn {name, task} ->
      unknown = Enum.reject(task.downstream, &(&1 in names))

      if unknown != [],
        do:
          raise(
            ArgumentError,
            "task #{inspect(name)}: unknown downstream tasks #{inspect(unknown)}"
          )
    end)

    graph =
      Graph.link_tasks(
        Enum.map(tasks, fn {name, task} -> {name, [downstream: task.downstream]} end)
      )

    with {:ok, stages} <- Graph.to_stages(graph) do
      {:ok,
       %Definition{
         name: Path.basename(file_path, extension()),
         adapter: :shell,
         file_path: file_path,
         options:
           for(
             {key, value} <- Map.take(yaml, Map.keys(@dag_opts)),
             do: {Map.fetch!(@dag_opts, key), value}
           ),
         task_list: List.flatten(stages),
         stages: stages,
         tasks:
           Map.new(tasks, fn {name, task} -> {name, Map.merge(task, Map.fetch!(graph, name))} end)
       }}
    end
  end

  defp parse_task!(task) do
    validate_keys!(task, @task_opts)
    name = Map.get(task, "name")
    command = Map.get(task, "run")
    downstream = Map.get(task, "downstream", [])
    store_result = Map.get(task, "store_result", Map.get(task, "save", false))

    unless is_binary(name) and name != "",
      do: raise(ArgumentError, "name must be a non-empty string")

    unless is_binary(command), do: raise(ArgumentError, "run must be a string")

    Template.validate!(command)

    validate_downstream!(downstream)

    unless is_boolean(store_result),
      do: raise(ArgumentError, "save/store_result must be a boolean")

    if Map.has_key?(task, "save") and Map.has_key?(task, "store_result"),
      do: raise(ArgumentError, "use only one of save and store_result")

    {name,
     %{
       run: command,
       downstream: downstream,
       store_result: store_result,
       exec_opts: parse_exec_opts!(task)
     }}
  rescue
    error in ArgumentError ->
      name = if is_map(task), do: Map.get(task, "name"), else: nil

      reraise ArgumentError,
              [message: "task #{inspect(name)}: #{Exception.message(error)}"],
              __STACKTRACE__
  end

  defp validate_downstream!(downstream) do
    unless is_list(downstream) and Enum.all?(downstream, &is_binary/1),
      do: raise(ArgumentError, "downstream must be a list of task names")
  end

  defp validate_keys!(options, allowed) when is_map(options) do
    case Map.keys(options) -- allowed do
      [] ->
        :ok

      keys ->
        raise ArgumentError,
              "unknown keys #{inspect(keys)}, the allowed keys are: #{inspect(Enum.sort(allowed))}"
    end
  end

  defp validate_keys!(_options, _allowed),
    do: raise(ArgumentError, "options must be a YAML mapping")

  defp parse_exec_opts!(task) do
    options =
      task
      |> Map.take(Map.keys(@exec_opts))
      |> Enum.map(fn {key, value} -> {Map.fetch!(@exec_opts, key), value} end)

    keys = Keyword.keys(options)

    if length(keys) != length(Enum.uniq(keys)),
      do: raise(ArgumentError, "use only one of cd, cwd and working_dir")

    defaults =
      Enum.reject(@default_exec_opts, fn
        {key, _} -> key in keys
        key -> key in keys
      end)

    defaults ++ Enum.flat_map(options, fn {key, value} -> parse_exec_option!(key, value) end)
  end

  defp parse_exec_option!(key, value)
       when key in [:cd, :cgroup, :executable, :user] and is_binary(value),
       do: [{key, value}]

  defp parse_exec_option!(:group, value) when is_integer(value) or is_binary(value),
    do: [{:group, value}]

  defp parse_exec_option!(key, value)
       when key in [:debug, :kill_timeout, :success_exit_code] and is_integer(value) and
              value >= 0,
       do: [{key, value}]

  defp parse_exec_option!(:nice, value) when is_integer(value) and value >= -20 and value <= 19,
    do: [{:nice, value}]

  defp parse_exec_option!(:env, value) when is_map(value) do
    env =
      Enum.map(value, fn {key, item} ->
        unless is_binary(key) and (is_binary(item) or is_number(item) or is_boolean(item)),
          do: raise(ArgumentError, "env must map string keys to strings, numbers or booleans")

        if is_binary(item), do: Template.validate!(item)

        {key, to_string(item)}
      end)

    [{:env, env}]
  end

  defp parse_exec_option!(key, true) when key in [:pty, :pty_echo], do: [key]
  defp parse_exec_option!(key, false) when key in [:pty, :pty_echo], do: []
  defp parse_exec_option!(key, "null") when key in @std_keys, do: [{key, :null}]
  defp parse_exec_option!(key, "close") when key in @std_keys, do: [{key, :close}]

  defp parse_exec_option!(key, value) when key in @std_keys and is_binary(value),
    do: [{key, value}]

  defp parse_exec_option!(key, value),
    do: raise(ArgumentError, "invalid value #{inspect(value)} for option #{inspect(key)}")
end
