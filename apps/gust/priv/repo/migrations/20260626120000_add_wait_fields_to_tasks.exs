defmodule Gust.Repo.Migrations.AddWaitFieldsToTasks do
  use Ecto.Migration

  def change do
    alter table(:gust_tasks) do
      add :waiting_for, :string
      add :wait_satisfied_at, :utc_datetime
    end

    create index(:gust_tasks, [:run_id, :status, :waiting_for])
  end
end
