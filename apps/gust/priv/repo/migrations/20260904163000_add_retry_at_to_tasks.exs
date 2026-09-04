defmodule Gust.Repo.Migrations.AddRetryAtToTasks do
  use Ecto.Migration

  def change do
    alter table(:gust_tasks) do
      add :retry_at, :utc_datetime_usec
    end
  end
end
