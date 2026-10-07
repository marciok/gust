defmodule Gust.Repo.Migrations.CreateSourceMonitorStates do
  use Ecto.Migration

  def change do
    create table(:gust_source_monitor_states, primary_key: false) do
      add :id, :string, primary_key: true
      add :source_type, :string, null: false
      add :status, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end
  end
end
