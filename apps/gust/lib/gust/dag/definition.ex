defmodule Gust.DAG.Definition do
  @moduledoc false
  defstruct name: "",
            mod: nil,
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
          error: map(),
          messages: list(),
          task_list: list(),
          stages: list(),
          tasks: map(),
          file_path: String.t(),
          options: keyword()
        }

  def errors?(%__MODULE__{error: error}), do: map_size(error) > 0
end
