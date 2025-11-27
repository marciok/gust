defmodule Gust.Flows.Log do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  schema "logs" do
    field :level, :string
    field :attempt, :integer
    field :content, :string
    field :timestamp, :utc_datetime_usec
    belongs_to :task, Gust.Flows.Task

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(log, attrs) do
    log
    |> cast(attrs, [:task_id, :attempt, :level, :content])
    |> validate_required([:task_id, :attempt, :level, :content])
  end
end
