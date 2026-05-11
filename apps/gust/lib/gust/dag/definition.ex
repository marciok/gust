defmodule Gust.DAG.Definition do
  @moduledoc false
  defstruct name: "",
            mod: nil,
            adapter: :elixir,
            error: %{},
            messages: [],
            task_list: [],
            stages: [],
            tasks: %{},
            file_path: "",
            options: Keyword.new()

  @type t :: %__MODULE__{
          name: String.t(),
          mod: module() | nil,
          adapter: atom(),
          error: map(),
          messages: list(),
          task_list: list(),
          stages: list(),
          tasks: map(),
          file_path: String.t(),
          options: keyword()
        }

  @doc """
  Returns `true` if the given DAG definition has any errors, by checking that the `error` map is non-empty.
  """

  def empty_errors?(%__MODULE__{error: error}), do: map_size(error) == 0

  def to_json(%__MODULE__{} = dag_def), do: dag_def |> to_map() |> Jason.encode()

  def to_map(%__MODULE__{} = dag_def) do
    dag_def
    |> Map.from_struct()
    |> normalize_json_value()
  end

  defp normalize_json_value(%MapSet{} = set), do: set |> Enum.sort()

  defp normalize_json_value(list) when is_list(list) do
    if Keyword.keyword?(list) do
      list
      |> Enum.into(%{}, fn {key, value} -> {key, normalize_json_value(value)} end)
    else
      Enum.map(list, &normalize_json_value/1)
    end
  end

  defp normalize_json_value(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {key, normalize_json_value(value)} end)
  end

  defp normalize_json_value(value), do: value
end
