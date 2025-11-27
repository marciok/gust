defmodule Gust.Repo.Migrations.AddTaskError do
  use Ecto.Migration

  def change do
    alter table(:tasks) do
      add :error, :jsonb, default: "{}", null: false
    end
  end
end
