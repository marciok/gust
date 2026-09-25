defmodule GustShell.Template do
  @moduledoc """
  EEx templates for shell task commands and environment values.

  Templates are checked when the DAG is parsed and rendered when the task
  starts, so each attempt sees the current secrets and run params. A template
  can use:

    * `run_id`, the current run id
    * `run_params`, the params the run was triggered with
    * `params`, the task's own params, such as a `map_over` item
    * `Flows`, an alias for `Gust.Flows`
    * `secret!/1`, which returns a secret's value by name
    * `task_result!/1`, which returns the saved result of a task in the same run

  Example:

      run: "cargo build --release --target <%= run_params["target"] %>"
      env:
        TOKEN: '<%= secret!("REGISTRY_TOKEN") %>'
        VERSION: '<%= task_result!("read_version")["stdout"] %>'
  """

  @doc """
  Raises if `template` is not a valid EEx template.
  """
  def validate!(template) when is_binary(template) do
    EEx.compile_string(template)
    :ok
  rescue
    error in [EEx.SyntaxError, SyntaxError, TokenMissingError, MismatchedDelimiterError] ->
      reraise ArgumentError,
              [message: "invalid template: #{Exception.message(error)}"],
              __STACKTRACE__
  end

  @doc """
  Renders `template` for `task`.

  The run is only loaded when the template uses `run_params`.
  """
  def render(template, task) when is_binary(template) do
    compiled = EEx.compile_string(template)
    run_id = Map.get(task, :run_id)

    bindings = [run_id: run_id, params: Map.get(task, :params) || %{}]

    bindings =
      if uses_var?(compiled, :run_params),
        do: [{:run_params, Gust.Flows.get_run!(run_id).params || %{}} | bindings],
        else: bindings

    quoted =
      quote do
        alias Gust.Flows
        import GustShell.Template, only: [secret!: 1, task_result!: 1]
        unquote(compiled)
      end

    {rendered, _bindings} = Code.eval_quoted(quoted, bindings)
    rendered
  end

  defp uses_var?(quoted, name) do
    {_quoted, found?} =
      Macro.prewalk(quoted, false, fn
        {^name, _meta, context} = node, _found? when is_atom(context) -> {node, true}
        node, found? -> {node, found?}
      end)

    found?
  end

  @doc """
  Returns the value of the secret named `name`.

  Raises `Ecto.NoResultsError` if the secret does not exist.
  """
  def secret!(name) when is_binary(name), do: Gust.Flows.get_secret_by_name!(name).value

  @doc """
  Returns the saved result of the task named `name` in the current run.

  The task must have finished before this template renders, which a `downstream`
  dependency guarantees. Shell task results are maps with the string keys
  `"stdout"`, `"stderr"`, `"exit_code"` and `"status"`, or an empty map when
  the task does not have `save: true`.

  Raises `Ecto.NoResultsError` if the task does not exist.
  """
  defmacro task_result!(name) do
    quote do
      Gust.Flows.get_task_result_by_name_run!(unquote(name), var!(run_id))
    end
  end
end
