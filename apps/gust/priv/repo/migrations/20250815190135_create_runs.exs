defmodule Gust.Repo.Migrations.CreateRuns do
  use Ecto.Migration

  def change do
    create table(:runs) do
      add :dag_id, references(:dags, on_delete: :delete_all), null: false
      add :status, :string

      timestamps(type: :utc_datetime)
    end
  end
end
