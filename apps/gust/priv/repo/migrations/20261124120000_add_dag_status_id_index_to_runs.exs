defmodule Gust.Repo.Migrations.AddDagStatusIdIndexToRuns do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create index(:gust_runs, [:dag_id, :status, :id], concurrently: true)
    drop index(:gust_runs, [:dag_id], concurrently: true)
  end
end
