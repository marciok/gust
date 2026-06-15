defmodule Gust.Repo.Migrations.AddParamsToTasks do
  use Ecto.Migration

  def change do
    alter table(:gust_tasks) do
      add :params, :jsonb, default: "{}", null: false
    end
  end
end
