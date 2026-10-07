defmodule Gust.Repo.Migrations.NotifyDagSourceChanges do
  use Ecto.Migration

  def up do
    execute("""
    CREATE OR REPLACE FUNCTION notify_gust_dag_source_changes()
    RETURNS trigger AS $$
    BEGIN
      PERFORM pg_notify('gust-dag-source-changes', 'changed');
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE TRIGGER gust_dag_source_changes_trigger
    AFTER INSERT OR UPDATE OF name, content, format, version, enabled, start_time, end_time, description
    OR DELETE
    ON gust_dag_sources
    FOR EACH ROW
    EXECUTE FUNCTION notify_gust_dag_source_changes();
    """)
  end

  def down do
    execute("DROP TRIGGER IF EXISTS gust_dag_source_changes_trigger ON gust_dag_sources")
    execute("DROP FUNCTION IF EXISTS notify_gust_dag_source_changes()")
  end
end
