defmodule Gust.Repo.Migrations.RenameLegacyTablesWithGustPrefix do
  use Ecto.Migration

  @table_renames [
    %{
      old: "dags",
      new: "gust_dags",
      old_sequence: "dags_id_seq",
      new_sequence: "gust_dags_id_seq"
    },
    %{
      old: "runs",
      new: "gust_runs",
      old_sequence: "runs_id_seq",
      new_sequence: "gust_runs_id_seq"
    },
    %{
      old: "tasks",
      new: "gust_tasks",
      old_sequence: "tasks_id_seq",
      new_sequence: "gust_tasks_id_seq"
    },
    %{
      old: "logs",
      new: "gust_logs",
      old_sequence: "logs_id_seq",
      new_sequence: "gust_logs_id_seq"
    },
    %{old: "secrets", new: "gust_secrets", old_sequence: nil, new_sequence: nil}
  ]

  @constraint_renames [
    %{table: "gust_dags", old: "dags_pkey", new: "gust_dags_pkey"},
    %{table: "gust_runs", old: "runs_pkey", new: "gust_runs_pkey"},
    %{table: "gust_runs", old: "runs_dag_id_fkey", new: "gust_runs_dag_id_fkey"},
    %{table: "gust_tasks", old: "tasks_pkey", new: "gust_tasks_pkey"},
    %{table: "gust_tasks", old: "tasks_run_id_fkey", new: "gust_tasks_run_id_fkey"},
    %{table: "gust_logs", old: "logs_pkey", new: "gust_logs_pkey"},
    %{table: "gust_logs", old: "logs_task_id_fkey", new: "gust_logs_task_id_fkey"},
    %{table: "gust_secrets", old: "secrets_pkey", new: "gust_secrets_pkey"}
  ]

  @index_renames [
    %{old: "dags_name_index", new: "gust_dags_name_index"},
    %{old: "runs_dag_id_index", new: "gust_runs_dag_id_index"},
    %{old: "tasks_run_id_index", new: "gust_tasks_run_id_index"},
    %{old: "logs_task_id_index", new: "gust_logs_task_id_index"},
    %{old: "secrets_name_index", new: "gust_secrets_name_index"}
  ]

  def up do
    rename_tables(@table_renames, :up)
    rename_sequences(sequence_renames(), :up)
    rename_constraints(@constraint_renames, :up)
    rename_indexes(@index_renames, :up)
  end

  def down do
    rename_indexes(@index_renames, :down)
    rename_constraints(@constraint_renames, :down)
    rename_sequences(sequence_renames(), :down)
    rename_tables(Enum.reverse(@table_renames), :down)
  end

  defp rename_tables(renames, direction) do
    Enum.each(renames, fn rename ->
      case direction do
        :up ->
          rename_table_if_needed(rename.old, rename.new, rename.new_sequence)

        :down ->
          rename_table_if_needed(rename.new, rename.old, rename.old_sequence)
      end
    end)
  end

  defp rename_sequences(renames, direction) do
    rename_pairs(renames, direction, &rename_sequence_if_needed/2)
  end

  defp rename_constraints(renames, direction) do
    Enum.each(renames, fn rename ->
      case direction do
        :up ->
          rename_constraint_if_needed(rename.table, rename.old, rename.new)

        :down ->
          rename_constraint_if_needed(rename.table, rename.new, rename.old)
      end
    end)
  end

  defp rename_indexes(renames, direction) do
    rename_pairs(renames, direction, &rename_index_if_needed/2)
  end

  defp rename_pairs(renames, direction, rename_fun) do
    Enum.each(renames, fn rename ->
      case direction do
        :up -> rename_fun.(rename.old, rename.new)
        :down -> rename_fun.(rename.new, rename.old)
      end
    end)
  end

  defp sequence_renames do
    Enum.flat_map(@table_renames, fn rename ->
      case {rename.old_sequence, rename.new_sequence} do
        {nil, nil} -> []
        {old_sequence, new_sequence} -> [%{old: old_sequence, new: new_sequence}]
      end
    end)
  end

  defp rename_table_if_needed(old_name, new_name, sequence_name \\ nil) do
    execute("""
    DO $$
    DECLARE
      old_count bigint;
      new_count bigint;
      shared_columns text;
    BEGIN
      IF to_regclass('#{old_name}') IS NOT NULL AND to_regclass('#{new_name}') IS NOT NULL THEN
        EXECUTE format('SELECT count(*) FROM %I', '#{old_name}') INTO old_count;
        EXECUTE format('SELECT count(*) FROM %I', '#{new_name}') INTO new_count;

        IF old_count > 0 AND new_count > 0 THEN
          RAISE EXCEPTION 'Cannot rename table #{old_name} to #{new_name} because both tables contain data';
        ELSIF old_count > 0 THEN
          SELECT string_agg(format('%I', old_column.attname), ', ' ORDER BY old_column.attnum)
          INTO shared_columns
          FROM pg_attribute AS old_column
          JOIN pg_attribute AS new_column
            ON new_column.attrelid = to_regclass('#{new_name}')
           AND new_column.attname = old_column.attname
           AND new_column.attnum > 0
           AND NOT new_column.attisdropped
          WHERE old_column.attrelid = to_regclass('#{old_name}')
            AND old_column.attnum > 0
            AND NOT old_column.attisdropped;

          EXECUTE format(
            'INSERT INTO %I (%s) SELECT %s FROM %I',
            '#{new_name}',
            shared_columns,
            shared_columns,
            '#{old_name}'
          );

          #{maybe_set_sequence_value(sequence_name, new_name)}
        END IF;

        EXECUTE format('DROP TABLE %I CASCADE', '#{old_name}');
      ELSIF to_regclass('#{old_name}') IS NOT NULL THEN
        ALTER TABLE "#{old_name}" RENAME TO "#{new_name}";
      END IF;
    END
    $$;
    """)
  end

  defp rename_index_if_needed(old_name, new_name) do
    execute("""
    DO $$
    BEGIN
      IF to_regclass('#{old_name}') IS NOT NULL AND to_regclass('#{new_name}') IS NOT NULL THEN
        RAISE EXCEPTION 'Cannot rename index #{old_name} to #{new_name} because both indexes exist';
      ELSIF to_regclass('#{old_name}') IS NOT NULL THEN
        ALTER INDEX "#{old_name}" RENAME TO "#{new_name}";
      END IF;
    END
    $$;
    """)
  end

  defp rename_sequence_if_needed(old_name, new_name) do
    execute("""
    DO $$
    BEGIN
      IF to_regclass('#{old_name}') IS NOT NULL AND to_regclass('#{new_name}') IS NOT NULL THEN
        RAISE EXCEPTION 'Cannot rename sequence #{old_name} to #{new_name} because both sequences exist';
      ELSIF to_regclass('#{old_name}') IS NOT NULL THEN
        ALTER SEQUENCE "#{old_name}" RENAME TO "#{new_name}";
      END IF;
    END
    $$;
    """)
  end

  defp rename_constraint_if_needed(table_name, old_name, new_name) do
    execute("""
    DO $$
    BEGIN
      IF EXISTS (
           SELECT 1
           FROM pg_constraint
           WHERE conrelid = '#{table_name}'::regclass
             AND conname = '#{old_name}'
         ) AND EXISTS (
           SELECT 1
           FROM pg_constraint
           WHERE conrelid = '#{table_name}'::regclass
             AND conname = '#{new_name}'
         ) THEN
        RAISE EXCEPTION 'Cannot rename constraint #{old_name} to #{new_name} on table #{table_name} because both constraints exist';
      ELSIF EXISTS (
              SELECT 1
              FROM pg_constraint
              WHERE conrelid = '#{table_name}'::regclass
                AND conname = '#{old_name}'
            ) THEN
        ALTER TABLE "#{table_name}" RENAME CONSTRAINT "#{old_name}" TO "#{new_name}";
      END IF;
    END
    $$;
    """)
  end

  defp maybe_set_sequence_value(nil, _table_name), do: ""

  defp maybe_set_sequence_value(sequence_name, table_name) do
    """
    EXECUTE format(
      'SELECT setval(%L, COALESCE((SELECT max(id) FROM %I), 1), true)',
      '#{sequence_name}',
      '#{table_name}'
    );
    """
  end
end
