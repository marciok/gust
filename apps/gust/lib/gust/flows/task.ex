defmodule Gust.Flows.Task do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  schema "gust_tasks" do
    field :name, :string

    field :status, Ecto.Enum,
      values: [
        :created,
        :running,
        :succeeded,
        :failed,
        :retrying,
        :upstream_failed,
        :skipped,
        :enqueued
      ],
      default: :created

    field :result, :map, default: %{}
    field :error, :map, default: %{}
    field :attempt, :integer, default: 1
    field :map_index, :integer
    belongs_to :run, Gust.Flows.Run
    has_many :logs, Gust.Flows.Log

    timestamps(type: :utc_datetime)
  end

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t() | nil,
          status:
            :created
            | :running
            | :succeeded
            | :failed
            | :retrying
            | :upstream_failed
            | :skipped
            | :enqueued,
          result: map(),
          error: map(),
          attempt: integer(),
          map_index: integer() | nil,
          run_id: integer() | nil,
          run: Gust.Flows.Run.t() | Ecto.Association.NotLoaded.t(),
          logs: [Gust.Flows.Log.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @doc false
  def changeset(task, attrs) do
    task
    |> cast(attrs, [:name, :status, :run_id, :result, :attempt, :error, :map_index])
    |> validate_required([:name, :status, :run_id, :result, :error])
  end

  @doc false
  def test_changeset(run, attrs) do
    run
    |> cast(attrs, [
      :inserted_at,
      :updated_at,
      :name,
      :status,
      :run_id,
      :result,
      :attempt,
      :error,
      :map_index
    ])
    |> validate_required([:name, :status, :run_id, :result, :error])
  end
end
