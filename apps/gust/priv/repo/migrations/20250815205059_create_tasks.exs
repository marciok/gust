defmodule Gust.Repo.Migrations.CreateTasks do
  use Ecto.Migration

  def change do
    create table(:tasks) do
      add :name, :string
      add :status, :string
      add :result, :jsonb, default: "{}", null: false
      add :run_id, references(:runs, on_delete: :delete_all), null: false
      add :attempt, :integer, default: 1

      timestamps(type: :utc_datetime)
    end

    create index(:tasks, [:run_id])
    create index(:runs, [:dag_id])
  end
end
