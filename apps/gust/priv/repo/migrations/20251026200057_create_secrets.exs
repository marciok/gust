defmodule Gust.Repo.Migrations.CreateSecrets do
  use Ecto.Migration

  def change do
    create table(:secrets, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :value, :binary, null: false
      add :value_type, :string, null: false

      timestamps()
    end

    create unique_index(:secrets, [:name])
  end
end
