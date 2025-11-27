defmodule Gust.Flows.Run do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  schema "runs" do
    belongs_to :dag, Gust.Flows.Dag

    field :status, Ecto.Enum,
      values: [:created, :running, :succeeded, :failed, :retrying, :enqueued],
      default: :created

    has_many :tasks, Gust.Flows.Task

    timestamps(type: :utc_datetime)
  end

  @type t :: %__MODULE__{
          id: integer() | nil,
          dag_id: integer() | nil,
          status: :created | :running | :succeeded | :failed | :retrying | :enqueued,
          tasks: [Gust.Flows.Task.t()] | Ecto.Association.NotLoaded.t(),
          dag: Gust.Flows.Dag.t() | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @doc false
  def changeset(run, attrs) do
    run
    |> cast(attrs, [:dag_id, :status])
    |> validate_required([:dag_id, :status])
  end

  @doc false
  def test_changeset(run, attrs) do
    run
    |> cast(attrs, [:dag_id, :status, :inserted_at])
    |> validate_required([:dag_id, :status])
  end
end
