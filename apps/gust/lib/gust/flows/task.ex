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
        :enqueued,
        :waiting
      ],
      default: :created

    field :result, :map, default: %{}
    field :error, :map, default: %{}
    field :params, :map, default: %{}
    field :waiting_for, :string
    field :wait_satisfied_at, :utc_datetime
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
            | :enqueued
            | :waiting,
          result: map(),
          error: map(),
          params: map(),
          waiting_for: String.t() | nil,
          wait_satisfied_at: DateTime.t() | nil,
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
    |> cast(attrs, [
      :name,
      :status,
      :run_id,
      :result,
      :attempt,
      :error,
      :params,
      :waiting_for,
      :wait_satisfied_at,
      :map_index
    ])
    |> validate_required([:name, :status, :run_id, :result, :error, :params])
    |> task_identity_constraints()
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
      :params,
      :waiting_for,
      :wait_satisfied_at,
      :map_index
    ])
    |> validate_required([:name, :status, :run_id, :result, :error, :params])
    |> task_identity_constraints()
  end

  defp task_identity_constraints(changeset) do
    changeset
    |> unique_constraint([:run_id, :name],
      name: :gust_tasks_run_id_name_unmapped_index
    )
    |> unique_constraint([:run_id, :name, :map_index],
      name: :gust_tasks_run_id_name_map_index_mapped_index
    )
  end
end
