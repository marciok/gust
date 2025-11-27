defmodule Gust.DAG.ErrorParser do
  @moduledoc false
  def parse(error) do
    %{
      type: inspect(error.__struct__),
      message: Exception.message(error)
    }
  end
end
