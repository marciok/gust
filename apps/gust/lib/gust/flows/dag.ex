defmodule Gust.Flows.Dag do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "dags" do
    field :name, :string
    field :enabled, :boolean, default: true
    has_many :runs, Gust.Flows.Run

    timestamps(type: :utc_datetime)
  end

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t() | nil,
          enabled: boolean(),
          runs: [Gust.Flows.Run.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @doc false
  def changeset(dag, attrs) do
    dag
    |> cast(attrs, [:name, :enabled])
    |> validate_required([:name])
    |> validate_format(:name, ~r/^[a-z0-9_]+$/,
      message: "must be lowercase, no spaces, only letters, numbers, and underscores"
    )
    |> unique_constraint(:name)
  end
end
