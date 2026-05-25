defmodule Gust.Repo.Migrations.AddParamsToGustRuns do
  use Ecto.Migration

  def change do
    alter table(:gust_runs) do
      add :params, :map, default: %{}, null: false
    end
  end
end
