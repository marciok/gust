defmodule Gust.DagSource do
  @moduledoc """
  Ecto schema for the gust_dag_sources table.

  Stores DAG definitions with optional time-based scheduling windows.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "gust_dag_sources" do
    field :name, :string
    field :content, :string
    field :format, :string, default: "elixir"
    field :version, :integer, default: 1
    field :enabled, :boolean, default: true
    field :start_time, :utc_datetime
    field :end_time, :utc_datetime
    field :description, :string

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Create a changeset for inserting/updating a DAG source.
  """
  def changeset(dag_source, attrs) do
    dag_source
    |> cast(attrs, [
      :name,
      :content,
      :format,
      :version,
      :enabled,
      :start_time,
      :end_time,
      :description
    ])
    |> validate_required([:name, :content, :format])
    |> unique_constraint(:name)
  end

  @doc """
  Check if a DAG source is currently active (within its time window and enabled).

  Returns true if:
    - enabled = true
    - start_time is NULL or in the past (or current time >= start_time)
    - end_time is NULL or in the future (or current time <= end_time)
  """
  def active?(dag_source, now \\ DateTime.utc_now()) do
    dag_source.enabled &&
      (is_nil(dag_source.start_time) || DateTime.compare(dag_source.start_time, now) != :gt) &&
      (is_nil(dag_source.end_time) || DateTime.compare(dag_source.end_time, now) != :lt)
  end
end
