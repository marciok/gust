defmodule Gust.Repo.Migrations.CreateLogs do
  use Ecto.Migration

  def change do
    create table(:logs) do
      add :attempt, :integer
      add :level, :string
      add :content, :text
      add :timestamp, :utc_datetime_usec
      add :task_id, references(:tasks, on_delete: :delete_all)

      timestamps(type: :utc_datetime)
    end

    create index(:logs, [:task_id])
  end
end
