defmodule Gust.Repo.Migrations.AddClaimFieldsToRuns do
  use Ecto.Migration

  def change do
    alter table(:gust_runs) do
      add :claimed_by, :string
      add :claim_expires_at, :utc_datetime_usec
      add :claim_token, :uuid
    end

    create index(:gust_runs, [:status, :claim_expires_at])
    create index(:gust_runs, [:claimed_by])
  end
end
