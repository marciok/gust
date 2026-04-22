defmodule Gust.Repo.Migrations.CreateDags do
  use Ecto.Migration

  def change do
    create table(:gust_dags) do
      add :name, :string, null: false
      add :enabled, :boolean, default: true, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:gust_dags, [:name])
  end
end
