defmodule Gust.Repo.Migrations.CreateDagSources do
  use Ecto.Migration

  def change do
    create table(:gust_dag_sources) do
      add :name, :string, null: false
      add :content, :text, null: false
      add :format, :string, null: false, default: "elixir"
      add :version, :integer, default: 1
      add :enabled, :boolean, default: true
      add :start_time, :utc_datetime
      add :end_time, :utc_datetime
      add :description, :text

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:gust_dag_sources, [:name])
    create index(:gust_dag_sources, [:enabled, :start_time])
    create index(:gust_dag_sources, [:updated_at])
  end
end
