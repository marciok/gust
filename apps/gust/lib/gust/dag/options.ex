defmodule Gust.DAG.Options do
  @moduledoc """
  Validates DAG options and reads settings from them, for every adapter.

  The options a DAG accepts:

    * `schedule` - a crontab expression, e.g. `"* * * * *"` or `"@daily"`.
    * `on_finished_callback` - the name of the function called when a run
      finishes.
    * `runs` - run-level settings. `retention: [max_count: n]` keeps the N
      most recent finished runs, and `Gust.Run.Pruner` deletes older ones.

  Elixir DAGs pass options to `use Gust.DSL` and are checked with
  `validate/1`. Python DAGs pass a dict with string keys, converted by
  `from_json/1` using fixed allowlists, so keys never become atoms. Unknown
  top-level keys from Python are ignored; unknown keys inside `runs` are
  errors.

  Invalid options are a DAG definition error, like a syntax error in the DAG
  file: the DAG is listed with the error and isn't scheduled, pruned or
  triggered. Valid options that won't take effect are reported as warnings by
  `warnings/2`.
  """

  alias Crontab.CronExpression.Parser, as: CronParser
  alias Gust.DAG.Definition
  alias Gust.Run.Pruner

  @keys [:schedule, :on_finished_callback, :runs]
  @runs_keys [:retention]
  @retention_keys [:max_count]

  @json_keys [
    {"on_finished_callback", :on_finished_callback},
    {"schedule", :schedule},
    {"runs", :runs}
  ]
  @json_runs_keys %{"retention" => :retention, "max_count" => :max_count}

  @pruning_off_warning "runs retention is set but pruning is off: " <>
                         "set config :gust, :run_pruner, schedule: \"...\""

  @doc """
  Validates the options of a DAG.
  """
  @spec validate(term()) :: {:ok, keyword()} | {:error, String.t()}
  def validate(options) do
    with :ok <- validate_keys(options, @keys, nil),
         :ok <- validate_schedule(Keyword.get(options, :schedule)),
         :ok <- validate_callback(Keyword.get(options, :on_finished_callback)),
         :ok <- validate_runs(Keyword.get(options, :runs)) do
      {:ok, options}
    end
  end

  @doc """
  Converts options decoded from JSON into a keyword list and validates them.
  """
  @spec from_json(map()) :: {:ok, keyword()} | {:error, String.t()}
  def from_json(json) do
    options =
      for {json_key, key} <- @json_keys, Map.has_key?(json, json_key) do
        {key, json[json_key]}
      end

    with {:ok, options} <- runs_from_json(options) do
      validate(options)
    end
  end

  @doc """
  Builds the `error` and `messages` of a definition whose options are invalid,
  shaped like a compile error so it's reported the same way.
  """
  @spec definition_error(String.t(), String.t()) :: {CompileError.t(), [map()]}
  def definition_error(file_path, message) do
    description = "invalid DAG options: #{message}"

    {%CompileError{file: file_path, line: 0, description: description},
     [diagnostic(file_path, description, :error)]}
  end

  @doc """
  Returns warnings, shaped like compiler warnings, for valid options that
  won't take effect: a `runs` retention while the `:run_pruner` schedule is
  unset or invalid, so the DAG's runs would never be pruned.
  """
  @spec warnings(keyword(), String.t()) :: [map()]
  def warnings(options, file_path) do
    if retention_max_count(options) != nil and not match?({:ok, _schedule}, Pruner.schedule()) do
      [diagnostic(file_path, @pruning_off_warning, :warning)]
    else
      []
    end
  end

  @doc """
  Returns the retention `max_count` of a DAG definition, or `nil` when unset.
  """
  @spec max_count(Definition.t()) :: pos_integer() | nil
  def max_count(%Definition{options: options}), do: retention_max_count(options)

  defp retention_max_count(options), do: get_in(options, [:runs, :retention, :max_count])

  defp diagnostic(file_path, message, severity) do
    %{
      message: message,
      severity: severity,
      file: file_path,
      source: file_path,
      position: 0,
      span: nil,
      stacktrace: []
    }
  end

  defp runs_from_json(options) do
    case Keyword.fetch(options, :runs) do
      {:ok, nil} ->
        {:ok, Keyword.delete(options, :runs)}

      {:ok, runs} ->
        with {:ok, runs} <- nested_from_json(runs) do
          {:ok, Keyword.replace!(options, :runs, runs)}
        end

      :error ->
        {:ok, options}
    end
  end

  defp nested_from_json(value) when is_map(value) do
    Enum.reduce_while(value, {:ok, []}, fn {key, val}, {:ok, acc} ->
      with {:ok, atom_key} <- json_runs_key(key),
           {:ok, converted} <- nested_from_json(val) do
        {:cont, {:ok, acc ++ [{atom_key, converted}]}}
      else
        error -> {:halt, error}
      end
    end)
  end

  defp nested_from_json(value), do: {:ok, value}

  defp json_runs_key(key) do
    case Map.fetch(@json_runs_keys, key) do
      {:ok, atom_key} -> {:ok, atom_key}
      :error -> {:error, "unknown key #{inspect(key)} in runs"}
    end
  end

  defp validate_schedule(nil), do: :ok

  defp validate_schedule(schedule) when is_binary(schedule) do
    case CronParser.parse(schedule) do
      {:ok, _cron} -> :ok
      {:error, reason} -> {:error, "invalid schedule #{inspect(schedule)}: #{reason}"}
    end
  end

  defp validate_schedule(schedule) do
    {:error, "schedule must be a crontab expression string, got: #{inspect(schedule)}"}
  end

  defp validate_callback(callback) when is_atom(callback) or is_binary(callback), do: :ok

  defp validate_callback(callback) do
    {:error, "on_finished_callback must be a function name, got: #{inspect(callback)}"}
  end

  defp validate_runs(nil), do: :ok

  defp validate_runs(runs) do
    with :ok <- validate_keys(runs, @runs_keys, "runs") do
      validate_retention(Keyword.get(runs, :retention))
    end
  end

  defp validate_retention(nil), do: :ok

  defp validate_retention(retention) do
    with :ok <- validate_keys(retention, @retention_keys, "runs retention") do
      validate_max_count(Keyword.fetch(retention, :max_count))
    end
  end

  defp validate_max_count({:ok, max_count}) when is_integer(max_count) and max_count > 0,
    do: :ok

  defp validate_max_count({:ok, max_count}) do
    {:error, "runs retention max_count must be a positive integer, got: #{inspect(max_count)}"}
  end

  defp validate_max_count(:error), do: {:error, "runs retention requires max_count"}

  defp validate_keys(value, allowed, name) do
    if Keyword.keyword?(value) do
      case Keyword.validate(value, allowed) do
        {:ok, _value} ->
          :ok

        {:error, keys} ->
          {:error,
           "unknown keys #{inspect(keys)} in #{location(name, value)}, the allowed keys are: #{inspect(allowed)}"}
      end
    else
      {:error, "#{name || "DAG options"} must be a keyword list, got: #{inspect(value)}"}
    end
  end

  defp location(nil, value), do: inspect(value)
  defp location(name, value), do: "#{name} #{inspect(value)}"
end
